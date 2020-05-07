// Copyright 2015 The Gorilla WebSocket Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// +build ignore

// Use with go run, not go build

package main

import (
	"log"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"time"

	"github.com/gorilla/websocket"
)

type Message struct {
	Type      string
	Author    string `JSON:"Author,omitempty"`
	Message   string
	Timestamp int64
}

type UsernameChange struct {
	Type     string
	Username string
}

var recCounter, connCounter int

func connect() {
	interrupt := make(chan os.Signal, 1)
	signal.Notify(interrupt, os.Interrupt)

	u := url.URL{Scheme: "ws", Host: "localhost:8090", Path: "/"}
	log.Printf("connecting to %s", u.String())

	c, _, err := websocket.DefaultDialer.Dial(u.String(), nil)
	if err != nil {
		log.Fatal("dial:", err)
	}
	defer c.Close()

	done := make(chan struct{})

	err = c.WriteJSON(UsernameChange{Type: "Username_Change", Username: c.LocalAddr().String()})
	if err != nil {
		log.Println("write:", err)
		return
	}

	connCounter++

	go func() {
		defer close(done)
		for {
			_, _, err := c.ReadMessage()
			if err != nil {
				log.Println("read:", err)
				return
			}
			//log.Printf("recv: %s", message)
			recCounter++
		}
	}()

	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	counter := 0

	for {
		select {
		case <-done:
			return
		case t := <-ticker.C:
			err := c.WriteJSON(Message{Type: "Message", Message: strconv.Itoa(counter), Timestamp: t.Unix()})
			if err != nil {
				log.Println("write:", err)
				return
			}
			counter++
		case <-interrupt:
			log.Println("interrupt")

			// Cleanly close the connection by sending a close message and then
			// waiting (with timeout) for the server to close the connection.
			err := c.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
			if err != nil {
				log.Println("write close:", err)
				return
			}
			select {
			case <-done:
			case <-time.After(time.Second):
			}
			return
		}
	}
}

func main() {
	log.SetFlags(0)

	interrupt := make(chan os.Signal, 1)
	signal.Notify(interrupt, os.Interrupt)

	for i := 0; i < 400; i++ {
		go connect()
	}

	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			log.Println(recCounter, connCounter)
		case <-interrupt:
			return
		}
	}

}
