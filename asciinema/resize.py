import json
import sys
import os
import argparse

parser = argparse.ArgumentParser(
    description="Resize an asciinema cast file by modifying its width and height in the header."
)

parser.add_argument("input_file", help="Path to the .cast file to resize")
parser.add_argument("width", type=int, help="New width for the terminal")
parser.add_argument("height", type=int, help="New height for the terminal")

args = parser.parse_args()

input_file = args.input_file
width = args.width
height = args.height

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
    output_file = f"{base_name}-resized.cast"
    # open the output file
    with open(output_file, "w") as out_f:
        # read all lines
        lines = f.readlines()
        # parse the first line as json
        header = json.loads(lines[0])
        # set width to 100
        header["width"] = width
        # set height to 35
        header["height"] = height
        # write the modified header line
        out_f.write(json.dumps(header) + "\n")
        # copy all subsequent lines as is
        for line in lines[1:]:
            out_f.write(line)

# move the output file to replace the input file
os.replace(input_file, f"{input_file}.not-resized.bak")
os.replace(output_file, input_file)