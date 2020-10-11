import matplotlib.pyplot as plt
import numpy as np

# GLOBAL parameters
clk = 1536000


def add_1_neg(num):
    if num < 0:
        return num + 1
    else:
        return num


# Print acc vs. freq function.
def plot_acc_vs_freq(file_name, start_freq):
    samp_rate = 1
    with open(file_name, 'rb') as f:
        buf = f.read()
        data_read = np.frombuffer(buf, dtype='int8')
        data8b_1 = [add_1_neg(i) for i in data_read[0::3]]
        data8b_2 = [add_1_neg(i) for i in data_read[1::3]]
        data8b_3 = data_read[2::3]

        data = np.add(np.add(np.multiply(data8b_1, 256), np.multiply(data8b_2, 16)), data8b_3)
        x = np.arange(start_freq, start_freq + 1.0 * samp_rate / 200000 * (len(data)), 1.0 / 200000 * samp_rate)

        plt.figure('Figure')
        plt.plot(x[0:len(data)], data)
        plt.xlabel('Frequency[Hz]', fontsize=14)
        plt.ylabel('Acc', fontsize=14)
        plt.title('Acc vs. Frequency', fontsize=20)
        plt.show()



# Print acc vs. freq function.
def plot_acc_vs_freq_fromlist(file_name, start_freq, list):
    samp_rate = 1
    data = np.flip(np.array(list))
    x = np.arange(start_freq, start_freq + 1.0 * samp_rate / 200000 * (len(data)), 1.0 / 200000 * samp_rate)

    plt.figure('Figure')
    plt.plot(x[0:len(data)], data)
    plt.xlabel('Frequency[Hz]', fontsize=14)
    plt.ylabel('Acc', fontsize=14)
    plt.title('Acc vs. Frequency', fontsize=20)
    plt.show()


# Print acc vs. time domain.
def plot_val_vs_time(file_name):
    samp_rate = 193
    with open(file_name, 'rb') as f:
        buf = f.read()
        data_read = np.frombuffer(buf, dtype='int8')
        data8b_1 = [add_1_neg(i) for i in data_read[0::3]]
        data8b_2 = [add_1_neg(i) for i in data_read[1::3]]
        data8b_3 = data_read[2::3]

        data = np.add(np.add(np.multiply(data8b_1, 256), np.multiply(data8b_2, 16)), data8b_3)
        x = np.arange(0, 1.0 * samp_rate / clk * (len(data)), 1.0 / clk * samp_rate)

        plt.figure('Figure')
        plt.plot(x[0:len(data)], data)
        plt.xlabel('Time[sec]', fontsize=14)
        plt.ylabel('Value', fontsize=14)
        plt.title('Input Value vs. Time', fontsize=20)
        #plt.show()



# Print acc vs. time domain.
def plot_val_vs_time_fromlist(file_name, List):
     samp_rate = 1
     data = np.array(List)
     x = np.arange(0, 1.0 * samp_rate / clk * (len(data)), 1.0 / clk * samp_rate)

     plt.figure('Figure')
     plt.plot(x[0:len(data)], data)
     plt.xlabel('Time[sec]', fontsize=14)
     plt.ylabel('Value', fontsize=14)
     plt.title('Input Value vs. Time', fontsize=20)
     #plt.show()


###### final opinion!

start_freq = 0

def setStartFreq(get_start_freq):
    global start_freq
    start_freq = get_start_freq


acc_vs_freq = np.array([])


def append_acc_vs_freq(List):
    global acc_vs_freq
    acc_vs_freq = np.append(acc_vs_freq, np.flip(np.array(List)))


# Print acc vs. freq function.
def plot_acc_vs_freq_global(not_used):
    global acc_vs_freq
    global start_freq
    samp_rate = 1
    data = acc_vs_freq
    x = np.arange(start_freq, start_freq + 1.0 * samp_rate / 200000 * (len(data)), 1.0 / 200000 * samp_rate)

    plt.figure('Figure')
    plt.plot(x[0:len(data)], data)
    plt.xlabel('Frequency[Hz]', fontsize=14)
    plt.ylabel('Acc', fontsize=14)
    plt.title('Acc vs. Frequency', fontsize=20)
    plt.show()
    acc_vs_freq = np.array([])


acc_vs_freq = np.array([])


def append_val_vs_time(List):
    global acc_vs_freq
    acc_vs_freq = np.append(List,acc_vs_freq)


# Print acc vs. time domain.
def plot_val_vs_time_global():
    global acc_vs_freq
    samp_rate = 1
    data = np.array(acc_vs_freq)
    x = np.arange(0, 1.0 * samp_rate / clk * (len(data)), 1.0 / clk * samp_rate)
    plt.figure('Figure')
    plt.plot(x[0:len(data)], data)
    plt.xlabel('Time[sec]', fontsize=14)
    plt.ylabel('Value', fontsize=14)
    plt.title('Input Value vs. Time', fontsize=20)
    plt.show()
    acc_vs_freq = np.array([])
