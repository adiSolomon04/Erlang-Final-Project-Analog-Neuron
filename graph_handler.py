import matplotlib.pyplot as plt
import numpy as np

# GLOBAL parameters
clk = 1536000


def calc_sign(num):
    if num < 0:
        return -1
    else:
        return 1


def calc_sign_add(num):
    if num < 0:
        return 1
    else:
        return 0


def add_1_neg(num):
    if num < 0:
        return num + 1
    else:
        return num


def plot_waves():
    with open('var.txt', 'rb') as f_var:
        [start_freq] = [0]  # [int(x) for x in next(f_var).split()]
        print(start_freq)

    with open('output_file.pcm', 'rb') as f:
        buf = f.read()
        data = np.frombuffer(buf, dtype='int16')
        sig_1 = data[0::2]
        sig_2 = data[1::2]
        x = np.arange(start_freq, start_freq + 1.0 / clk * 193 * (len(sig_1) - 1), 1.0 / clk * 193)
        fig1 = plt.figure(1)
        plt.plot(x, sig_1[1:len(sig_1 - 1)])
        fig2 = plt.figure(2)
        plt.plot(x, sig_2[1:len(sig_2)])

    with open('input_wave.pcm', 'rb') as f:
        buf = f.read()
        data1 = np.frombuffer(buf, dtype='int8')

        data8b_1 = [add_1_neg(i) for i in data1[0::3]]
        data8b_2 = [add_1_neg(i) for i in data1[1::3]]
        data8b_3 = data1[2::3]
        ## Take 3 numbers.
        # data = (data[i]+1)*256+(data[i+1]+1)*16+data[i+2] (negative nums)
        # data = (data[i])*256+(data[i+1])*16+data[i+2] pos nums.

        sig = np.add(np.add(np.multiply(data8b_1, 256), np.multiply(data8b_2, 16)), data8b_3)

        # data8b_1_signed = data1[1::2]   #[int.from_bytes(i, byteorder='big') for i in data1[1::2]]
        # data8b_sign = [calc_sign(i) for i in data8b_2] # -1 for negative, +1 else
        # data8b_sign_add = [calc_sign_add(i) for i in data8b_2]      # 1  for negative, 0 else
        # data8b_unsigned = np.add(np.multiply(data8b_2, data8b_sign), np.multiply(2**7, data8b_sign_add))
        # data8b_1_sign = [calc_sign(i) for i in data8b_1]
        ## the 16 bit final calc
        # sig = np.add(np.multiply(data8b_1,256),np.multiply(data8b_unsigned, data8b_1_sign)) #data1 #[1:len(data1)-1]

        print(len(sig))
        x1 = np.arange(start_freq, start_freq + 1.0 / clk * 193 * (len(sig)), 1.0 / clk * 193)
        print(len(x1))
        fig3 = plt.figure(3)
        plt.plot(x1[0:len(x1)], sig)
        plt.show()


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

