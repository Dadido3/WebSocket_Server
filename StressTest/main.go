package main

import (
	"crypto/rand"
	"flag"
	"log"
	"net/url"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var addr = flag.String("addr", "localhost:8090", "http service address")
var path = flag.String("path", "/", "http path")

func main() {
	flag.Parse()

	// Setup test options and test data that is sent over and received from every server connection.

	randomData := make([]byte, 4096)
	rand.Read(randomData)

	testOptions := TestOptions{
		URL: url.URL{Scheme: "ws", Host: *addr, Path: *path},
		Packets: []TestPacket{
			{Type: websocket.TextMessage, Payload: []byte("Test")},
			{Type: websocket.TextMessage, Payload: []byte("Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet.")},
			{Type: websocket.BinaryMessage, Payload: []byte{123}},
			{Type: websocket.BinaryMessage, Payload: randomData},
			{Type: websocket.TextMessage, Payload: []byte("1")},
			{Type: websocket.TextMessage, Payload: []byte("2")},
			{Type: websocket.TextMessage, Payload: []byte("3")},
			{Type: websocket.TextMessage, Payload: []byte("4")},
			{Type: websocket.TextMessage, Payload: []byte("5")},
			{Type: websocket.TextMessage, Payload: []byte("12")},
			{Type: websocket.BinaryMessage, Payload: []byte("Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet.")},
		},
	}

	wg := &sync.WaitGroup{}
	for i := 0; i < 200; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()

			for true {

				res, err := DoConnectionTest(testOptions)
				if err != nil {
					log.Printf("Error: %v", err)
					time.Sleep(3000 * time.Millisecond)
				} else {
					log.Printf("Full roundtrip latency: %v", res.FullRoundtripLatency)
					time.Sleep(100 * time.Millisecond)
				}

			}
		}()
	}
	wg.Wait()
}
