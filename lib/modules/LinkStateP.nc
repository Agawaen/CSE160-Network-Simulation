#define LSA_REFRESH_INTERVAL 10000

module LinkStateP{
    provides interface LinkState;
    uses interface NeighborDiscovery;
    uses interface Flooding;
    uses interface SimpleSend;
    uses interface Receive as Receiver;
    uses interface Timer<TMilli> as LSATimer;
    uses interface Dijkstra;
}

implementation {
    typedef struct {
        uint16_t nextHop;
        uint16_t cost;
    } destTuple;
    
    // Structure for link state data
    typedef struct {
        uint8_t src;
        uint8_t seqNum;
        uint8_t neighborsNum;
        destTuple neighbors[MAX_NEIGHBORS];
    } LSAPacket; // Link-State advertise packet

    uint8_t seqNum = 0;
    uint16_t ttl = MAX_TTL;
    uint8_t linkStatePayload[MAX_NEIGHBORS];
    uint8_t payloadLength = sizeof(linkStatePayload);
    pack sendReq;

    uint8_t neighborGraph[MAX_NEIGHBORS][MAX_NEIGHBORS];

    uint8_t* tempPayload = ""; // just for testing


    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);
    void initializeLSAPackage();
    bool isNeighborGraphFilled();
    void loadDistanceTable();
    
    command void LinkState.advertise() {
        dbg(GENERAL_CHANNEL, "Initializing Link State Advertise at node %d\n", TOS_NODE_ID);
        initializeLSAPackage();
        call Flooding.flood(0);
        call LSATimer.startPeriodic(LSA_REFRESH_INTERVAL);
    }

    event message_t* Receiver.receive(message_t* msg, void* payload, uint8_t len) {
        if (len == sizeof(pack)) {
            pack* package = (pack*)payload;
            if (package->protocol == PROTOCOL_LINKSTATE) {
                dbg(ROUTING_CHANNEL, "LSA Package Received at Node %d\n", TOS_NODE_ID);
            }
        }
    }

    event void LSATimer.fired() {
    uint8_t i;
    uint8_t j;
    uint8_t nodeCount = 0;
    bool hasConnection;

    uint8_t* tempGraph = call Flooding.getNeighborGraph();
    dbg(ROUTING_CHANNEL, "LSATimer: Getting neighbor graph from Flooding\n");
    
    for (i = 0; i < MAX_NEIGHBORS; i++) {
        dbg(ROUTING_CHANNEL, "LSATimer: Row %d neighbors:", i);
        hasConnection = FALSE;
        for (j = 0; j < MAX_NEIGHBORS; j++) {
            uint16_t idx = i * MAX_NEIGHBORS + j;
            // Normalize the values: if it's greater than 0, set to 1
            if (tempGraph[idx] > 0) {
                neighborGraph[i][j] = 1;
                dbg(ROUTING_CHANNEL, " %d\n", j);
                hasConnection = TRUE;
            } else {
                neighborGraph[i][j] = 0;
            }
        }
        if (hasConnection) {
            nodeCount++;
        }
        dbg(ROUTING_CHANNEL, "\n");
    }
    
    if (isNeighborGraphFilled()) {
        dbg(ROUTING_CHANNEL, "Neighbor graph filled; Creating Routing Table\n");
        loadDistanceTable();
    } else {
        dbg(ROUTING_CHANNEL, "Neighbor graph not filled; Current nodes with connections: %d\n", nodeCount);
    }
}

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
        Package->src = src; // Link Layer Head
        Package->dest = dest; // Link Layer Head
        Package->TTL = TTL; // Flooding Header
        Package->seq = seq; // Flooding Header
        Package->protocol = protocol; // Flooding Header
        memcpy(Package->payload, payload, length);
    }

    void initializeLSAPackage() {
        // linkStatePayload->src = TOS_NODE_ID;
        // linkStatePayload->seqNum = 0;
        // linkStatePayload->neighborsNum = call NeighborDiscovery.getNeighborCount();
    }

    // void initializeNeighborGraph() {
    //     uint16_t i;
    //     uint16_t j;

    //     for (i = 0; i < MAX_NEIGHBORS; i++) {
    //         for (j = 0; j < MAX_NEIGHBORS; j++) {
    //             routingGraph[i][j] = UINT16_MAX;
    //         }
    //     }
    // }

    // void updateRoutingTable(uint16_t dist[], uint16_t src) {
    //     uint16_t i;
    //     for (i = 0; i < MAX_NEIGHBORS; i++) {
    //         if (i != src && routingTable[i].cost < dist[i] + routing[src].cost) {
    //             routingTable[i].nextHop = src;
    //             routingTable[i].cost = dist[i] + routing[src].cost;
    //         }
    //     }
    // }

    void loadDistanceTable() {
    uint8_t i;
    uint8_t j;
    uint8_t nextHop;
    uint8_t numNeighbors;
    bool hasValidPath;

    // Debug the neighbor graph first
    dbg(ROUTING_CHANNEL, "Direct neighbors of node %d:", TOS_NODE_ID);
    for (i = 0; i < MAX_NEIGHBORS; i++) {
        dbg(ROUTING_CHANNEL, "neighborGraph[%d][%d] = %d\n", TOS_NODE_ID, i, neighborGraph[TOS_NODE_ID][i]);
        if (neighborGraph[TOS_NODE_ID][i] == 1) {
            dbg(ROUTING_CHANNEL, " %d", i);
            numNeighbors++;
        }
    }
    dbg(ROUTING_CHANNEL, "\nTotal direct neighbors: %d\n", numNeighbors);

    // Run Dijkstra's algorithm
    call Dijkstra.make((uint8_t*)neighborGraph, TOS_NODE_ID);

    dbg(ROUTING_CHANNEL, "Printing routing table for node %d\n", TOS_NODE_ID);
    
    // Generate routing table
    for (i = 0; i < MAX_NEIGHBORS; i++) {
        if (i == TOS_NODE_ID) {
            dbg(ROUTING_CHANNEL, "%d -> %d (self)\n", i, TOS_NODE_ID);
            continue;
        }

        nextHop = call Dijkstra.getNextHop(i);
        hasValidPath = FALSE;

        // If destination is a direct neighbor
        if (neighborGraph[TOS_NODE_ID][i] == 1) {
            nextHop = i;
            hasValidPath = TRUE;
            dbg(ROUTING_CHANNEL, "%d -> %d (direct)\n", i, nextHop);
        }
        // If Dijkstra found a valid path
        else if (nextHop != UINT8_MAX && nextHop != TOS_NODE_ID && neighborGraph[TOS_NODE_ID][nextHop] == 1) {
            hasValidPath = TRUE;
            dbg(ROUTING_CHANNEL, "%d -> %d (via Dijkstra)\n", i, nextHop);
        }
        // Try to find a path through neighbors
        else {
            for (j = 0; j < MAX_NEIGHBORS; j++) {
                if (neighborGraph[TOS_NODE_ID][j] == 1 && neighborGraph[j][i] == 1) {
                    nextHop = j;
                    hasValidPath = TRUE;
                    dbg(ROUTING_CHANNEL, "%d -> %d (via neighbor)\n", i, nextHop);
                    break;
                }
            }
        }

        if (!hasValidPath) {
            dbg(ROUTING_CHANNEL, "%d -> %d (no route)\n", i, TOS_NODE_ID);
        }
    }
}

    void updateNeighborGraph(uint16_t neighborTable[], uint16_t src) {
        uint16_t i;

        for (i = 0; i < MAX_NEIGHBORS; i++) {
            if (neighborTable[i] > 0)
                neighborGraph[src][i] = 1;
            else
                neighborGraph[src][i] = 0;
        }
    }

    bool isNeighborGraphFilled() {
        uint8_t i;
        uint8_t j;
        uint8_t receivedCount = 0;

        for (i = 0; i < MAX_NEIGHBORS; i++) {
            for (j = 0; j < MAX_NEIGHBORS; j++) {
                if (neighborGraph[i][j] != 0) {
                    receivedCount++;
                    break;
                }
            }
        }

        return (receivedCount >= 5);
    }
}