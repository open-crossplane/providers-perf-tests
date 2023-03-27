#!/usr/bin/env python3
import pandas as pd
import matplotlib.pyplot as plt

def plot_data(data, x_column, y_column, unit, title, filename):
    data_version_a = data[data['Version'] == 'v0.29.0-e45875a']
    data_version_b = data[data['Version'] == 'v0.29.0-e45875b']

    plt.plot(data_version_a[x_column], data_version_a[y_column], marker='o', label='v0.29.0-e45875a')
    plt.plot(data_version_b[x_column], data_version_b[y_column], marker='o', label='v0.29.0-e45875b')

    plt.xlabel(x_column + ' (' + unit + ')')
    plt.ylabel(y_column + ' (' + unit + ')')
    plt.title(title)
    plt.legend()

    plt.savefig(filename)
    plt.clf()  # Clear the current figure for the next plot

# Read the CSV file
data = pd.read_csv('test_data.csv', delimiter=';')
data.columns = data.columns.str.strip()

# Create separate graphs for each column
plot_data(data, 'Runs', 'Experiment Duration', 'seconds', 'Experiment Duration vs Test Runs', 'experiment_duration.png')
plot_data(data, 'Runs', 'Average Time to Readiness in seconds', 'seconds', 'Average Time to Readiness vs Test Runs', 'avg_time_readiness.png')
plot_data(data, 'Runs', 'Peak Time to Readiness in seconds', 'seconds', 'Peak Time to Readiness vs Test Runs', 'peak_time_readiness.png')
plot_data(data, 'Runs', 'Average Memory', 'MB', 'Average Memory vs Test Runs', 'avg_memory.png')
plot_data(data, 'Runs', 'Peak Memory', 'MB', 'Peak Memory vs Test Runs', 'peak_memory.png')
plot_data(data, 'Runs', 'Average CPU', 'percentage', 'Average CPU Usage vs Test Runs', 'avg_cpu.png')
plot_data(data, 'Runs', 'Peak CPU', 'percentage', 'Peak CPU Usage vs Test Runs', 'peak_cpu.png')
#  plt.show()
