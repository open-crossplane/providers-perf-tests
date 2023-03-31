#!/usr/bin/env python3
import os
import re
import glob
import argparse

def process_file(file_path):
    file_basename = os.path.basename(file_path)
    match = re.match(r'test_[^_]+_(\w+)_(.+?)_(\d+)\.txt', file_basename)
    if match:
        platform, version, run = match.groups()
    else:
        raise ValueError(f"Invalid file name format: {file_basename}")

    with open(file_path) as f:
        content = f.read()
        content = content.split("Experiment Ended")[-1]
        values = re.findall(r'msg=".*? (\d+\.?\d*)', content)

    formatted_values = [
        f"{float(val):.2f}" if "." in val else val for val in values
    ]

    return f"{platform}_{version};{run.rstrip('.txt')};{';'.join(formatted_values)}"

parser = argparse.ArgumentParser(description="Process raw data files.")
parser.add_argument('--raw_data_folder', default='raw-data', help="Path to the raw data folder.")
parser.add_argument('--file_pattern', default="test_*.txt", help="File pattern to match.")
args = parser.parse_args()

raw_data_folder = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', args.raw_data_folder)
file_pattern = os.path.join(raw_data_folder, args.file_pattern)

files = glob.glob(file_pattern)

headers = "Version;Runs;Experiment Duration;Average Time to Readiness in seconds ;Peak Time to Readiness in seconds ;Average Memory;Peak Memory;Average CPU %;Peak CPU %"
combined_results = [headers]

for file_path in files:
    combined_results.append(process_file(file_path))

output = "\n".join(combined_results)
print(output)
