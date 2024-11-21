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

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);
    
    // Allocates new socket(s)
    command socket_t Transport.socket(){
        uint16_t i;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            if (sockets[i].state == CLOSED){
                // listen state
                sockets[i].state = LISTEN;
                dbg(TRANSPORT_CHANNEL, "Socket allocated with ID: %d\n", i);
                return i; // Return socket ID
            }
        }
        dbg(TRANSPORT_CHANNEL, "No sockets available\n");
        return NULL_SOCKET; // No Sockets available
    }

    // if (sockets[fd].state == LISTEN){
    //     call LinkState.send(packet);
    //     dbg(TRANSPORT_CHANNEL, "Call LSP to socket")
    // }

    // Binds socket with an address and port
    command error_t Transport.bind(socket_t fd, socket_addr_t *addr){

        if (sockets[fd].state == LISTEN){

            addr->addr = TOS_NODE_ID;
            sockets[fd].src = 80; 
            addr->port = 80; 
            dbg(TRANSPORT_CHANNEL, "Socket binds to address %d, port %d\n", TOS_NODE_ID, addr->port);
            return SUCCESS; // Able to bind
        }
        dbg(TRANSPORT_CHANNEL, "Unable to bind\n");
        return FAIL; // Unable to bind
    }

    // Accepts incoming connectivity
    command socket_t Transport.accept(socket_t fd){
        if (sockets[fd].state == LISTEN) {
            // Check if SYN packet is ready to accept
            if (sockets[fd].state == SYN_RCVD){
                // ESTABLISHED transition 
                sockets[fd].state = ESTABLISHED; 
                dbg(TRANSPORT_CHANNEL, "Socket %d accepted connection from %d\n", fd, sockets[fd].dest.addr);
                return fd;
            }
        }
        dbg(TRANSPORT_CHANNEL, "Socket %d cannot accept connection (no SYN recieved\n", fd);
        return NULL_SOCKET;
    }

    // Send data from buffer through the socket
    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen){
        /* Goal: Take data from a buffer and create TCP packs, 
        > Send them over network, handles buffering (and retransmissions)
        */
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

        if (fd >= MAX_NUM_OF_SOCKETS || fd < 0)
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

        makePack(closePackage, TOS_NODE_ID, dest, MAX_TTL, PROTOCOL_TCP, 0, currentSocket, sizeof(socket_store_t));
        call LinkState.send(closePackage);

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

            if (package->protocol == PROTOCOL_TCP){
                if (package->dest == TOS_NODE_ID) {
                    // makePack(&sendReq, TOS_NODE_ID, package->src, MAX_TTL, PROTOCOL_TCP, package->seq, pingPayload, pingPayloadLength);
                    // call LinkState.send(sendReq);
                    dbg(ROUTING_CHANNEL, "TCP Package received at %d from %d\n", TOS_NODE_ID, package->src);
                } else {
                    dbg(ROUTING_CHANNEL, "Forwarding TCP Package\n");
                    call LinkState.send(*package);
                }
            }
        }
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