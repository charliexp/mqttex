defmodule MqttexEncoderTest do
	@moduledoc """
	This test checks the encoding of regular Elixir structs to binary messages.
	"""
	# require Lager
	# import Bitwise
	use ExUnit.Case

	test "length encoding one byte" do
		assert Mqttex.Encoder.encode_length(127) == <<0x7f>>
		assert Mqttex.Encoder.encode_length(0) == <<0x00>>
	end

	test "length encoding two bytes" do
		assert Mqttex.Encoder.encode_length(128) == <<0x80,0x01>>
		assert Mqttex.Encoder.encode_length(16_383) == <<0xFF, 0x7F>>
	end

	test "length encoding three bytes" do
		assert Mqttex.Encoder.encode_length(16_384) == <<0x80, 0x80, 0x01>>
		assert Mqttex.Encoder.encode_length(2_097_151) == <<0xFF, 0xFF, 0x7F>>
	end

	test "length encoding four bytes" do
		assert Mqttex.Encoder.encode_length(2_097_152) == <<0x80, 0x80, 0x80, 0x01>>
		assert Mqttex.Encoder.encode_length(268_435_455) == <<0xFF, 0xFF, 0xFF, 0x7F>>
	end

	test "length encoding with more then four bytes fails" do
		catch_error Mqttex.Encoder.encode_length(268_435_456)
	end

	test "fixed header encoding" do
		header = %Mqttex.Msg.FixedHeader{}
		assert Mqttex.Encoder.encode_header(header) == <<0x00, 0x00>>
		assert Mqttex.Encoder.encode_header(Mqttex.Msg.fixed_header(:subscribe, 
			true, :exactly_once, true, 127)) == <<0x8d, 0x7f>>
	end

	test "very simple messages without message ids" do
		assert Mqttex.Encoder.encode(Mqttex.Msg.ping_req()) == <<0xc0, 0x00>>
		assert Mqttex.Encoder.encode(Mqttex.Msg.ping_resp()) == <<0xd0, 0x00>>
		assert Mqttex.Encoder.encode(Mqttex.Msg.disconnect()) == <<0xe0, 0x00>>
	end

	test "simple messages with message ids" do
		assert Mqttex.Encoder.encode(Mqttex.Msg.pub_ack(20)) == <<0x40, 0x02, 0x00, 20>>
		assert Mqttex.Encoder.encode(Mqttex.Msg.pub_rec(21)) == <<0x50, 0x02, 0x00, 21>>
		assert Mqttex.Encoder.encode(Mqttex.Msg.pub_comp(22)) == <<0x70, 0x02, 0x00, 22>>
	end

	test "connect message" do
		connect = Mqttex.Msg.connection("client Nr. 1", "", "", true)
		assert Mqttex.Encoder.encode(connect) == <<16, 26, 0, 6, "MQIsdp", 3, 
			2, 0, 0, 0, 12, "client Nr. 1">>
	end

	test "subscribe message" do
		subscribe = Mqttex.Msg.subscribe([{"topic 1", :fire_and_forget}])
		assert Mqttex.Encoder.encode(subscribe) == <<0x82, subscribe.header.length, 
			0x00, 0x00, 
			0x00, 0x07, "topic 1", 0>>
	end

	test "sub_ack message" do
		sub_ack = Mqttex.Msg.sub_ack([:fire_and_forget, :exactly_once], 23)
		assert %Mqttex.Msg.FixedHeader{} = sub_ack.header
		assert Mqttex.Encoder.encode(sub_ack) == <<0x90, 0x04,
			0x00, 23, 0x00, 0x02>>
	end

	test "publish message fire and forget" do
		pub = Mqttex.Msg.publish("a/b", "Hello", :fire_and_forget, 37)
		assert Mqttex.Encoder.encode(pub) == <<0x30, 10, 
			0x00, 0x03, "a/b", 
			"Hello">>
	end

	test "publish message exactly_once" do
		pub = Mqttex.Msg.publish("a/b", "Hello", :exactly_once, 37)
		assert Mqttex.Encoder.encode(pub) == <<0x34, 12, 
			0x00, 0x03, "a/b", 
			0x00, 37,
			"Hello">>
	end

end