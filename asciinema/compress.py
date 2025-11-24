import json
import sys
import os
import argparse

# Create argument parser
parser = argparse.ArgumentParser(
    description='Compress asciinema cast files by adjusting timing between events.'
)
parser.add_argument(
    'input_file',
    help='Input .cast file to compress'
)
parser.add_argument(
    'min_delta',
    type=float,
    help='Minimum time delta between events (in seconds)'
)
parser.add_argument(
    'max_delta',
    type=float,
    help='Maximum time delta between events (in seconds)'
)

# Parse arguments
args = parser.parse_args()

# get the input file name as CLI arg
input_file = args.input_file
# get the minimum delta time from CLI args
min_delta = args.min_delta
# get the maximum delta time from CLI args
max_delta = args.max_delta

with open(input_file) as f:
    # base name without extension
    base_name = input_file.rsplit(".", 1)[0]
    # extension
    extension = input_file.rsplit(".", 1)[1]
    #bail out if extension is not cast
    if extension != "cast":
        print("Input file must be a .cast file")
        sys.exit(1)
    # output file name
    output_file = f"{base_name}-compressed.cast"
    # open the output file
    with open(output_file, "w") as out_f:
        # read all lines
        lines = f.readlines()
        # write the first line as is
        out_f.write(lines[0])
        # set current time to zero
        current_time = 0.0
        # set last time to zero
        last_time = 0.0
        # for each subsequent line, parse as json, then re-dump without spaces
        for line in lines[1:]:
            parsed = json.loads(line)
            # parsed is a list with three elements, timestamp, type, data
            # bind the elements to variables for clarity
            timestamp, typ, data = parsed
            # set delta = timestamp - last_time
            delta = timestamp - last_time
            # set new delta = min (delta, max_delta)
            if delta < max_delta:
                new_delta = min_delta
            else:
                new_delta = max_delta
            # update current_time += new_delta
            current_time += new_delta
            # update last_time = timestamp
            last_time = timestamp
            output = [current_time, typ, data]
            j = json.dumps(output, separators=(', ', ': ')) + "\n"
            out_f.write(j)

# move the output file to replace the input file
os.replace(input_file, f"{input_file}.not-compressed.bak")
os.replace(output_file, input_file)