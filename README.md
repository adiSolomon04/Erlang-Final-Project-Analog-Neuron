# Parallel and distributed implementation of analog neurons' network and a resonator in Erlang
 This is the final project of "Functional programming in concurrent and distributed systems"
 
- ### General Info:
 
 The main purpose of the project is to implement neural network distributed on several computers. 
 
 The client chooses a frequency to calculate, how many neurons there will be in the network (4 or 17) and whether the network will be distributed on one computer or 4 computers.

- ### How to Run:

First in every computer, run compilation from the project file
```
erl -make
```

 Then we open an erlang shell, setting the same coockie in every node, and then we open the GUI from the main node
```
neuron_server:start_link().
```

then the GUI is opened in the main computer, we choose how many neurons we want in our network, how many nodes will be involved in the network. we insert the nodes and then, we choose the wanted frequency to detect and after that we can launch the network, we can open several different networks if needed.
