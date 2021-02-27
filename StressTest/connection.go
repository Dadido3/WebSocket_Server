package main

import (
	"bytes"
	"fmt"
	"net/url"
	"time"

	"github.com/gorilla/websocket"
)

// TestPacket represents a single packet that will be sent to the server and is expected to be looped back.
type TestPacket struct {
	Type    int // The packet/message types are defined in RFC 6455
	Payload []byte
}

// TestOptions contains all needed test parameters and values for a single connection test.
type TestOptions struct {
	URL     url.URL
	Packets []TestPacket
}

// TestResult contains all measurable values from a single connection test.
type TestResult struct {
	TotalDuration         time.Duration // Total duration of DoConnectionTest.
	ConnectLatency        time.Duration // Duration to establish the websocket connection.
	FirstRoundtripLatency time.Duration // Roundtrip time of the first packet. This includes the duration it takes to send the message.
	FullRoundtripLatency  time.Duration // Roundtrip time of all packets. This includes the duration it takes to send the messages.
	DisconnectLatency     time.Duration // Duration for connection closure.
}

// DoConnectionTest connects to a given web-socket server.
// It will send and receive (a) message(s), and check the received message for correctness.
// This assumes that the server loops back any received message.
func DoConnectionTest(opt TestOptions) (TestResult, error) {
	startTime := time.Now()
	res := TestResult{}

	// Open connection.
	c, _, err := websocket.DefaultDialer.Dial(opt.URL.String(), nil)
	if err != nil {
		return res, err
	}
	defer c.Close()

	res.ConnectLatency = time.Now().Sub(startTime)

	// Receive data and/or handle errors or disconnects.
	done := make(chan error, 1)
	received := make(chan struct{})
	go func() {
		defer close(done)
		index := 0

		for {
			mType, message, err := c.ReadMessage()
			if err != nil {
				// Ignore error if the connection closed due to normal closure.
				if closeErr, ok := err.(*websocket.CloseError); ok && closeErr.Code == websocket.CloseNormalClosure {
					return
				}

				done <- err
				return
			}

			// Check if the amount is not over the expected packet amount.
			if index >= len(opt.Packets) {
				done <- fmt.Errorf("Received more packets that expected")
				return
			}

			// Get next expected packet.
			expectedPacket := opt.Packets[index]
			index++

			// Check if the packet type is correct.
			if expectedPacket.Type != mType {
				done <- fmt.Errorf("Received unexpected packet type")
				return
			}

			// Check if the payload is correct.
			if bytes.Compare(expectedPacket.Payload, message) != 0 {
				done <- fmt.Errorf("Received unexpected packet payload")
				return
			}

			// Measure roundtrip time of the first packet.
			if index == 1 {
				res.FirstRoundtripLatency = time.Now().Sub(startTime) - res.ConnectLatency
			}

			// Signal that everything expected has been received. But don't stop this listener yet.
			if index == len(opt.Packets) {
				close(received)
			}

		}
	}()

	// Send payload.
	for _, packet := range opt.Packets {
		err = c.WriteMessage(packet.Type, packet.Payload)
		if err != nil {
			return res, err
		}
	}

	// Wait either until all the data was received correctly, an error was encountered, or until a timeout is reached.
	select {
	case err := <-done:
		return res, err
	case <-received:
		res.FullRoundtripLatency = time.Now().Sub(startTime) - res.ConnectLatency
	case <-time.After(5 * time.Second):
		return res, fmt.Errorf("Receive timeout. Not all packets were received in time")
	}

	// Cleanly close connection.
	err = c.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
	if err != nil {
		return res, err
	}

	// Wait either until the connection is closed by the server (as reaction to the close message), or until a timeout is reached.
	select {
	case err := <-done:
		res.DisconnectLatency = time.Now().Sub(startTime) - res.FullRoundtripLatency
		res.TotalDuration = res.ConnectLatency + res.FullRoundtripLatency + res.DisconnectLatency
		return res, err
	case <-time.After(5 * time.Second):
		return res, fmt.Errorf("Closure timeout")
	}
}
