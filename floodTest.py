from TestSim import TestSim

def main():
    # Get simulation ready to run.
    s = TestSim();

    # Before we do anything, lets simulate the network off.
    s.runTime(10);

    # Load the the layout of the network.
    s.loadTopo("long_line.topo");

    # Add a noise model to all of the motes.
    s.loadNoise("no_noise.txt");

    # Turn on all of the sensors.
    s.bootAll();

    # Add the main channels. These channels are declared in includes/channels.h
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);
    s.addChannel(s.FLOODING_CHANNEL);

    # After sending a ping, simulate a little to prevent collision.
    s.runTime(1);
    s.ping(2, 6, "Hello, World");
    s.runTime(1);

    # After FLOODING EVENT, s.flood(node), s.runtime(reruns clock)
    s.flood(3, 0);
    s.runTime(1);
    s.flood(7, 0);
    s.runTime(20);

if __name__ == '__main__':
    main()
