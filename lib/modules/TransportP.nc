#define MAX_NUM_OF_SOCKETS 1
#define NULL_SOCKET 255

#include "../../includes/socket.h"

module TransportP{
    provides interface Transport;
    uses interface SimpleSend;
    uses interface Receive as Receiver;
    uses interface Timer<TMilli> as sendTimer;
    uses interface LinkState; // call LinkState.send(packet, destination);
}

implementation{
    // Manage multiple sockets 
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    uint16_t destination;
    pack sendReq;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);
    
    // Allocates new socket(s)
    command socket_t Transport.socket(){
        uint16_t i;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            if (sockets[i].state == CLOSED){
                // listen state
                sockets[i].state = LISTEN;
                dbg(TRANSPORT_CHANNEL, "[Transport.socket] Socket allocated with ID: %d\n", i);
                return i; // Return socket ID
            }
        }
        dbg(TRANSPORT_CHANNEL, "[Transport.socket] No sockets available\n");
        return NULL_SOCKET; // No Sockets available
    }


    // SYN and ACK 

    // Binds socket with an address and port
    command error_t Transport.bind(socket_t fd, socket_addr_t *addr){

        dbg(TRANSPORT_CHANNEL, "[Transport.bind] Socket %d current state: %d\n", fd, sockets[fd].state);

        if (sockets[fd].state == LISTEN){

            addr->addr = TOS_NODE_ID;
            sockets[fd].src = 80; 
            addr->port = 80;
            dbg(TRANSPORT_CHANNEL, "Socket binds to address %d, port %d\n", TOS_NODE_ID, addr->port);

            makePack(&sendReq, TOS_NODE_ID, addr->addr, MAX_TTL, 
                    PROTOCOL_TCP, 0, (uint8_t*)&sockets[fd], sizeof(socket_store_t));
            call LinkState.send(sendReq);
            dbg(TRANSPORT_CHANNEL, "LSP packet sent for socket %d\n", fd);

            return SUCCESS; // Able to bind            
        }

        dbg(TRANSPORT_CHANNEL, "[Transport.bind] Unable to bind\n");
        return FAIL; // Unable to bind
    }


    // Accepts incoming connectivity
    command socket_t Transport.accept(socket_t fd){
        dbg(TRANSPORT_CHANNEL, "[Transport.accept] Socket %d state: %d\n", fd, sockets[fd].state);
        
        if (sockets[fd].state == LISTEN) {
            // Check if SYN packet is ready to accept
            sockets[fd].state = SYN_RCVD;
            dbg(TRANSPORT_CHANNEL, "[Transport.accept] Socket %d now waiting for SYN\n", fd);
                // ESTABLISHED transition 
                // sockets[fd].state = ESTABLISHED; 
                dbg(TRANSPORT_CHANNEL, "[Transport.accept] Socket %d accepted connection from %d\n", fd, sockets[fd].dest.addr);
                return fd;
        }
        dbg(TRANSPORT_CHANNEL, "[Transport.accept] Socket %d cannot accept connection (no SYN recieved)\n", fd);
        return NULL_SOCKET;
    }

    // Send data from buffer through the socket
    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen){
        uint16_t write;
        uint16_t writeLen;
        uint8_t i;
        if (sockets[fd].state != ESTABLISHED) {
            dbg(TRANSPORT_CHANNEL, "Write failed, Socket %d is not established\n", fd);
            /* Goal: Take data from a buffer and create TCP packs, 
        > Send them over network, handles buffering (and retransmissions)
        */
        return 0;
        }
        dbg(TRANSPORT_CHANNEL, "Writing... Socket %d is established\n", fd);
        if (bufflen < SOCKET_BUFFER_SIZE){
            write = bufflen;
        }
        else {
            writeLen = SOCKET_BUFFER_SIZE;
        }
        
        for (i = 0; i < writeLen; i++) {
            sockets[fd].sendBuff[i] = buff[i];
        }
        return 0;
    }


    command error_t Transport.receive(pack* package){
        /* Goal: Processes incoming TCP packets
        > Transport layer would parse incoming packets, (validate)
        update socket states or buffers (for handling incoming data)
        */
        return 0;
    }

    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen){
        /* Goal: Reads data from a socket into a buffer
        > fetches recived data from socket's recieve buffer,
        processes incoming data
        */
        return 0;
    }

    command error_t Transport.connect(socket_t fd, socket_addr_t * addr){
        /* Goal: Intiates a connection a remote socket
        > 3-way handshake (sending SYN and wait for SYN-ACK)
        > Set state to SYN_SENT during handshake
        */ 
        return 0;
    }

    command error_t Transport.close(socket_t fd){
        /* Goal: Close a socket
        > Clears buffers, resets variables
        */
        socket_store_t *currentSocket;
        pack *closePackage;
        uint16_t dest;
        uint8_t *payload;

        if (fd >= MAX_NUM_OF_SOCKETS)
            return FAIL;

        currentSocket = &sockets[fd];

        if (currentSocket->state == CLOSED)
            return SUCCESS;

        dest = currentSocket->dest.addr;
        
        currentSocket->state = CLOSED;

        memset(currentSocket->sendBuff, 0, SOCKET_BUFFER_SIZE);
        memset(currentSocket->rcvdBuff, 0, SOCKET_BUFFER_SIZE);

        currentSocket->lastWritten = 0;
        currentSocket->lastAck = 0;
        currentSocket->lastSent = 0;
        currentSocket->lastRead = 0;
        currentSocket->lastRcvd = 0;
        currentSocket->nextExpected = 0;
        currentSocket->RTT = 0;
        currentSocket->effectiveWindow = 0;

        currentSocket->src = 0;
        currentSocket->dest.port = 0;
        currentSocket->dest.addr = 0;

        makePack(closePackage, TOS_NODE_ID, dest, MAX_TTL, PROTOCOL_TCP, 0, (uint8_t*)currentSocket, sizeof(socket_store_t));
        call LinkState.send(*closePackage);

        dbg(TRANSPORT_CHANNEL, "Closed socket %d\n", fd);
        return SUCCESS;
    }

    command error_t Transport.release(socket_t fd){
        /* Goal: Forces hard close on socket
        > Terminates connection abruptly
        */
        return 0;
    }

    command error_t Transport.listen(socket_t fd){
        /* Goal: socket into listening state, waiting for incoming connections
        > Transitions socket state to LISTEN 
        */
        return 0;
    }

    event message_t* Receiver.receive(message_t* msg, void* payload, uint8_t len) {
        if (len == sizeof(pack)) {
            pack* package = (pack*)payload;
            uint8_t tcpPayload[SOCKET_BUFFER_SIZE];
            uint8_t tcpPayloadLength = 0;

            if (package->protocol == PROTOCOL_TCP){
                if (package->dest == TOS_NODE_ID) {
                    // Create TCP acknowledgment payload
                    tcpPayload[0] = 1;  // ACK flag
                    tcpPayload[1] = sockets[0].src;  // Source port
                    tcpPayload[2] = package->src;    // Destination port
                    tcpPayloadLength = 3;  // Basic TCP header length

                    // Create acknowledgment packet
                    makePack(&sendReq, TOS_NODE_ID, package->src, MAX_TTL, PROTOCOL_TCP, package->seq, tcpPayload, tcpPayloadLength);

                    call LinkState.send(sendReq);
                    dbg(ROUTING_CHANNEL, "TCP Package received at %d from %d\n", TOS_NODE_ID, package->src);
                } else {
                    dbg(ROUTING_CHANNEL, "Forwarding TCP Package\n");
                    call LinkState.send(*package);
                }
            }
        }
        return msg;
    }

    event void sendTimer.fired(){
        // Goal: Timer event for retranmission (previous tasks) 
        uint16_t i;
    }

    // Constructs a TCP packet, encapsulate data with headers
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
        Package->src = src; // Link Layer Head
        Package->dest = dest; // Link Layer Head
        Package->TTL = TTL; // Flooding Header
        Package->seq = seq; // Flooding Header
        Package->protocol = protocol; // Flooding Header
        memcpy(Package->payload, payload, length);
    }
}