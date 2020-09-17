import matplotlib.pyplot as plt
import numpy as np


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
        return num+1
    else:
        return num


def plot_waves():
    clk = 1536000
    with open('var.txt', 'rb') as f_var:
        [start_freq] = [0] #[int(x) for x in next(f_var).split()]
        print(start_freq)

    with open('output_file.pcm', 'rb') as f:
        buf = f.read()
        data = np.frombuffer(buf, dtype='int16')
        sig_1 = data[0::2]
        sig_2 = data[1::2]
        x = np.arange(start_freq, start_freq+1.0 / (clk)*193 * (len(sig_1)-1), 1.0 / (clk)*193)
        fig1 = plt.figure(1)
        plt.plot(x, sig_1[1:len(sig_1-1)])
        fig2 = plt.figure(2)
        plt.plot(x, sig_2[1:len(sig_2)])

    with open('input_wave.pcm', 'rb') as f:
        buf = f.read()
        data1 = np.frombuffer(buf, dtype='int8')
        ##dtype =np.dtype((np.int16, {'x': (np.int8, 0), 'y': (np.int8, 1)}))
        ### calc the 16 bit signed from 2 - 8bit signed.
        #data8b_unsigned = np.multiply(data1[0::2], 0x7FFF)
        data8b_1 = [add_1_neg(i) for i in data1[0::3]]
        data8b_2 = [add_1_neg(i) for i in data1[1::3]]
        data8b_3 = data1[2::3]
        ## Take 3 numbers.
        # data = (data[i]+1)*256+(data[i+1]+1)*16+data[i+2] (negative nums)
        # data = (data[i])*256+(data[i+1])*16+data[i+2] pos nums.

        sig = np.add(np.add(np.multiply(data8b_1, 256), np.multiply(data8b_2, 16)), data8b_3)

        print(len(sig))
        x1 = np.arange(start_freq, start_freq + 1.0 / clk * 193 * (len(sig)), 1.0 / clk * 193)
        print(len(x1))
        fig3 = plt.figure(3)
        plt.plot(x1[0:len(x1)], sig)
        plt.show()


#plot_waves()