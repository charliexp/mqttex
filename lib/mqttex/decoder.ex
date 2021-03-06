defmodule Mqttex.Decoder do
	@moduledoc """
	Decoding and encoding of MQTT messages.
	"""
	require Lager
	use Bitwise

	@type next_byte_fun :: (() -> {binary, next_byte_fun})
	@type read_message_fun :: ((pos_integer) -> binary)

	@type all_message_types :: Mqttex.Msg.Simple.t | Mqttex.Msg.Publish.t | Mqttex.Msg.SubAck.t | Mqttex.Mst.Unsubscibe.t

	# @type decode(binary, next_byte_fun, read_message_fun) :: all_message_types
	def decode(msg = <<_m :: size(16)>>, readByte, readMsg) do
		header = decode_fixheader(msg, readByte)
		Lager.info ("Header = #{inspect header}")
		var_m = readMsg.(header.length)
		Lager.info("decoding remaing messages #{inspect var_m}")
		decode_message(var_m, header)
	end

	@spec decode_fixheader(binary, next_byte_fun ) :: Mqttex.Msg.FixedHeader.t
	def decode_fixheader(<<type :: size(4), dup :: size(1), qos :: size(2), 
						   retain :: size(1), len :: size(8)>>, readByte) do
		Mqttex.Msg.fixed_header(binary_to_msg_type(type), 
			(dup == 1), binary_to_qos(qos),(retain == 1),
			binary_to_length(<<len>>, readByte))
	end

	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :publish}), do: decode_publish(msg, h)
	def decode_message(<<>>, %Mqttex.Msg.FixedHeader{message_type: :ping_req, length: 0}), 
		do: Mqttex.Msg.ping_req()
	def decode_message(<<>>, %Mqttex.Msg.FixedHeader{message_type: :ping_resp, length: 0}), 
		do: Mqttex.Msg.ping_resp()
	def decode_message(<<>>, %Mqttex.Msg.FixedHeader{message_type: :disconnect, length: 0}), 
		do: Mqttex.Msg.disconnect()
	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :pub_ack}), 
		do: Mqttex.Msg.pub_ack(get_msgid(msg))
	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :pub_rec}), 
		do: Mqttex.Msg.pub_rec(get_msgid(msg))
	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :pub_rel, qos: :at_least_once, duplicate: dup}), 
		do: Mqttex.Msg.pub_rel(get_msgid(msg), dup)
	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :pub_comp}), 
		do: Mqttex.Msg.pub_comp(get_msgid(msg))
	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :unsub_ack}), 
		do: Mqttex.Msg.unsub_ack(get_msgid(msg))
	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :subscribe}), do: decode_subscribe(msg, h)
	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :unsubscribe}), do: decode_unsubscribe(msg)
	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :sub_ack}), do: decode_sub_ack(msg)
	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :connect}), do: decode_connect(msg)
	def decode_message(<<_reserved :: bytes-size(1), status :: integer-size(8)>>, 
		h = %Mqttex.Msg.FixedHeader{message_type: :conn_ack}), 
		do: Mqttex.Msg.conn_ack(conn_ack_status(status))
		


	@spec decode_publish(binary, Mqttex.Msg.FixedHeader.t) :: Mqttex.Msg.Publish.t
	def decode_publish(msg, h) do
		{topic, m1} = utf8(msg)
		# in m1 is the message id if qos = 1 or 2
		{msg_id, payload} = case h.qos do
			:fire_and_forget -> {0, m1}
			_   -> 
				<<id :: unsigned-integer-size(16), content :: binary>> = m1
				{id, content}
		end
		## create a publish message 
		p = Mqttex.Msg.publish(topic, payload, h.qos)
		%Mqttex.Msg.Publish{ p | header: h, msg_id: msg_id}
	end

	@spec decode_unsubscribe(binary) :: Mqttex.Msg.Unsubscibe.t
	def decode_unsubscribe(<<msg_id :: unsigned-integer-size(16), content :: binary>>) do
		topics = utf8_list(content)
		Mqttex.Msg.unsubscribe(topics, msg_id)
	end

	@spec decode_sub_ack(binary) :: Mqttex.Msg.SubAck.t
	def decode_sub_ack(<<msg_id :: unsigned-integer-size(16), content :: binary>>) do
		granted_qos = qos_list(content)
		Mqttex.Msg.sub_ack(granted_qos, msg_id)
	end

	@spec decode_connect(binary) :: Mqttex.Msg.Conection.t
	def decode_connect(<<0x00, 0x06, "MQIsdp", 0x03, flags :: size(8), keep_alive :: size(16), rest::binary>>) do
		<<user_flag :: size(1), pass_flag :: size(1), w_retain :: size(1), w_qos :: size(2), 
			w_flag :: size(1), clean :: size(1), _ ::size(1)>> = <<flags>>
		{client_id, payload} = extract(1, utf8_list(rest))
		{will_topic, will_message, payload} = extract2(w_flag, payload)
		{user_name, payload} = extract(user_flag, payload)
		{password, payload} = extract(pass_flag, payload)

		alive = if (keep_alive == 0) do :infinity else keep_alive end		

		Mqttex.Msg.connection(client_id, user_name, password, clean == 1, alive,
			w_flag == 1, binary_to_qos(w_qos), w_retain == 1, will_topic, will_message)
	end

	@spec decode_subscribe(binary, Mqttex.Msg.FixedHeader.t) :: Mqttex.Msg.Subscribe.t
	def decode_subscribe(<<msg_id :: unsigned-integer-size(16), payload :: binary>>, h) do
		topics = topics(payload)
		%Mqttex.Msg.Subscribe{ Mqttex.Msg.subscribe(topics, msg_id) | header: h}
		#	Mqttex.Msg.Subscribe.duplicate(h.duplicate == 1)
	end
	
	def topics(<<>>, acc), do: Enum.reverse acc
	def topics(payload, acc \\ []) do
		{topic, rest} = utf8(payload)		
		<<qos :: size(8), r :: binary>> = rest
		topics(r, [{topic, binary_to_qos(qos)} | acc])  
	end
	

	@doc """
	Extracts the head of the list, if the flag is set and return the tail of list.
	Otherwise return the default value `""` and the unmodified list.
	"""
	@spec extract(integer, [binary]) :: {binary, [binary]}
	def extract(0, list), do: {"", list}
	def extract(1, list), do: {hd(list), tl(list)}

	@doc """
	Extracts the first 2 elements of the list, if the flag is set and return the rest of list.
	Otherwise return the default values `""` and the unmodified list.
	"""
	@spec extract2(integer, [binary]) :: {binary, binary, [binary]}
	def extract2(0, list), do: {"", "", list}
	def extract2(1, list), do: {hd(list), hd(tl list), tl(tl list)}
	
			
	@doc "Decodes a binary as list of qos entries"
	def qos_list(<<>>, acc), do: Enum.reverse acc
	def qos_list(<<q :: size(8), rest :: binary>>, acc \\ []) do
		qos_list(rest, [binary_to_qos(q) | acc])
	end
	


	@doc "Expects a 16 bit binary and returns its value as integer"
	@spec get_msgid(binary) :: integer	
	def get_msgid(<<id :: unsigned-integer-size(16)>>), do: id	

	@doc "Decodes an entire list of utf8 encodes strings"
	@spec utf8_list(binary, [binary]) :: [binary]
	def utf8_list(<<>>, acc), do: Enum.reverse acc
	def utf8_list(content, acc \\ []) do
		{t, rest} = utf8(content)
		utf8_list(rest, [t | acc])
	end
	


	@doc """
	Decodes an utf8 string (in the header) of a MQTT message. Returns the string and the
	remaining input message.
	"""
	@spec utf8(binary) :: {binary, binary}
	def utf8(<<length :: integer-unsigned-size(16), content :: bytes-size(length), rest :: binary>>) do
		{content, rest}
	end
	


	@spec binary_to_length(binary, integer, next_byte_fun) :: integer
	def binary_to_length(bin, count \\ 4, readByte_fun)
	def binary_to_length(_bin, count = 0, _readByte) do
		raise "Invalid length"
	end
	def binary_to_length(<<overflow :: size(1), len :: size(7)>>, count, readByte) do
		case overflow do
			1 ->
				{byte, nextByte} = readByte.() 
				len + (binary_to_length(byte, count - 1, nextByte) <<< 7)
			0 -> len
		end
	end


	@doc "convertes the binary qos to atoms"
	def binary_to_qos(0), do: :fire_and_forget
	def binary_to_qos(1), do: :at_least_once
	def binary_to_qos(2), do: :exactly_once
	def binary_to_qos(3), do: :reserved

	@doc "Converts the binary message type to atoms"
	def binary_to_msg_type(1), do: :connect
	def binary_to_msg_type(2), do: :conn_ack
	def binary_to_msg_type(3), do: :publish
	def binary_to_msg_type(4), do: :pub_ack
	def binary_to_msg_type(5), do: :pub_rec
	def binary_to_msg_type(6), do: :pub_rel
	def binary_to_msg_type(7), do: :pub_comp
	def binary_to_msg_type(8), do: :subscribe
	def binary_to_msg_type(9), do: :sub_ack
	def binary_to_msg_type(10), do: :unsubscribe
	def binary_to_msg_type(11), do: :unsub_ack
	def binary_to_msg_type(12), do: :ping_req
	def binary_to_msg_type(13), do: :ping_resp
	def binary_to_msg_type(14), do: :disconnect
	def binary_to_msg_type(0), do: :reserved
	def binary_to_msg_type(15), do: :reserved

	def conn_ack_status(0), do: :ok
	def conn_ack_status(1), do: :unaccaptable_protocol_version
	def conn_ack_status(2), do: :identifier_rejected
	def conn_ack_status(3), do: :server_unavailable
	def conn_ack_status(4), do: :bad_user
	def conn_ack_status(5), do: :not_authorized
	
	
end
