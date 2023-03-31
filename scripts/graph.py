#!/usr/bin/env python3
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

def convert_memory_units(value):
    value_mb = float(value) / (1024 * 1024)
    if value_mb >= 1000:
        value_gb = value_mb / 1024
        return f"{value_gb:.1f} GB"
    else:
        return f"{value_mb:.1f} MB"

def plot_data(data, x_column, y_column, unit, title, filename):
    versions = data['Version'].unique()
    for version in versions:
        data_version = data[data['Version'] == version]
        plt.plot(data_version[x_column], data_version[y_column], marker='o', label=version)

    if unit == 'memory':
        data[y_column] = data[y_column].apply(convert_memory_units)
        plt.ylabel(y_column)
    else:
        plt.ylabel(y_column + ('' if unit == '' else f' ({unit})'))
    plt.xlabel(x_column)

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
plot_data(data, 'Runs', 'Average Memory', 'GB', 'Average Memory vs Test Runs', 'avg_memory.png')
plot_data(data, 'Runs', 'Peak Memory', 'GB', 'Peak Memory vs Test Runs', 'peak_memory.png')
plot_data(data, 'Runs', 'Average CPU %', 'percentage', 'Average CPU Usage vs Test Runs', 'avg_cpu.png')
plot_data(data, 'Runs', 'Peak CPU %', 'percentage', 'Peak CPU Usage vs Test Runs', 'peak_cpu.png')

def plot_grouped_bar(data, x_column, y_column, unit, title, filename):
    plt.figure(figsize=(10, 6))
    if unit == 'memory':
        data[y_column] = data[y_column].apply(convert_memory_units)
        plt.ylabel(y_column)
    else:
        plt.ylabel(y_column + ('' if unit == '' else f' ({unit})'))
    sns.barplot(x=x_column, y=y_column, hue='Version', data=data, errorbar=None)
    plt.xlabel(x_column)
    plt.title(title)
    plt.legend()
    plt.savefig(filename)
    plt.clf()

# Now, update the memory-related plot calls to use 'memory' as the unit
plot_grouped_bar(data, 'Runs', 'Average Memory', 'GB', 'Average Memory vs Test Runs', 'avg_memory_grouped_bar.png')
plot_grouped_bar(data, 'Runs', 'Peak Memory', 'GB', 'Peak Memory vs Test Runs', 'peak_memory_grouped_bar.png')
plot_grouped_bar(data, 'Runs', 'Experiment Duration', 'seconds', 'Experiment Duration vs Test Runs', 'experiment_duration_grouped_bar.png')
plot_grouped_bar(data, 'Runs', 'Average Time to Readiness in seconds', 'seconds', 'Average Time to Readiness vs Test Runs', 'avg_time_readiness_grouped_bar.png')
plot_grouped_bar(data, 'Runs', 'Peak Time to Readiness in seconds', 'seconds', 'Peak Time to Readiness vs Test Runs', 'peak_time_readiness_grouped_bar.png')
plot_grouped_bar(data, 'Runs', 'Average CPU %', 'percentage', 'Average CPU Usage vs Test Runs', 'avg_cpu_grouped_bar.png')
plot_grouped_bar(data, 'Runs', 'Peak CPU %', 'percentage', 'Peak CPU Usage vs Test Runs', 'peak_cpu_grouped_bar.png')

