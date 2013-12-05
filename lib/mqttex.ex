defmodule Mqttex do
	use Application.Behaviour

  	# See http://elixir-lang.org/docs/stable/Application.Behaviour.html
  	# for more information on OTP Applications
  	def start(_type, _args) do
  		Mqttex.Supervisor.start_link
  	end

  	@type qos_type :: :fire_and_forget | :ack_delivery | :assured_delivery
	@type message_type :: :connect | :conn_ack | :publish | :pub_ack |
						:pub_rec | :pub_rel | :pub_comp | :subscribe |
						:sub_ack | :unsubscribe | :unsub_ack | 
						:ping_req | :ping_resp | :disconnect | :reserved

	@type conn_ack_type :: :ok | :unaccaptable_protocol_version | 
						:identifier_rejected | :server_unavailable | :bad_user |
						:not_authorized 

	# The fixed header of a MQTT message
	defrecord FixedHeader, 
		message_type: :reserved,
		duplicate: false,
		qos: :fire_and_forget,
		retain: false,
		length: 0			

	# The connection information for new connections
	defrecord Connection, 
		client_id: "",
		user_name: "",
		password: "",
		last_will: false,
		will_qos: :fire_and_forget,
		will_retain: false,
		will_topic: "",
		will_message: ""

	# The Connection message
	defrecord ConnectionMsg, header: FixedHeader.new, connection: Connection.new

	# The return code for a connection acknowledgement
	defrecord ConnAckMsg, status: :ok

	# The publish message
	defrecord PublishMsg, header: FixedHeader.new, topic: "", msg_id: 0, message: ""

	# The puback message
	defrecord PubAckMsg, msg_id: 0

	# The pubrec message
	defrecord PubRecMsg, msg_id: 0

	# The pubrel message
	defrecord PubRelMsg, header: FixedHeader.new, msg_id: 0

	# The pubcomp message
	defrecord PubCompMsg, msg_id: 0

	# The Subscribe message
	defrecord SubscribeMsg, header: FixedHeader.new, msg_id: 0, topics: [{"", :fire_and_forget}]

	# The Suback message
	defrecord SubAckMsg, msg_id: 0, granted_qos: []

	# The UnSubscribe message
	defrecord UnSubscribeMsg, header: FixedHeader.new, msg_id: 0, topics: []

	# The UnSubAck message
	defrecord UnSubAckMsg, msg_id: 0

	# The ping request message (status is only a field to have field, has no semantics)
	defrecord PingReqMsg, status: :ok

	# The ping response message (status is only a field to have field, has no semantics)
	defrecord PingRespMsg, status: :ok

	# The disconnect message (status is only a field to have field, has no semantics)
	defrecord DisconnectMsg, status: :ok
end