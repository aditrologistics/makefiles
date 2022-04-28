import argparse
import json
from typing import Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser("Update .env-files")
    parser.add_argument('--vars', type=str, required=True)
    parser.add_argument('--envfiles', type=str, required=True)
    parser.add_argument('-v', action='append', type=str, required=False)
    return parser.parse_args()


def convert_to_dict(vars: List[str]) -> Dict[str, str]:
    result = {}
    for _ in vars or []:
        pair = _.split("=", 2)
        if len(pair) != 2:
            print(f"Unable to parse ´{_}'")
            continue
        result[pair[0]] = pair[1]

    return result


def read_definitions(filename: str) -> Dict[str, str]:
    print(f"Opening {filename}")
    try:
        with open(filename) as f:
            data = json.load(f)
        return convert_to_dict(data)
    except json.decoder.JSONDecodeError:
        print("Unable to parse data!")
        raise


def read_text_file(filename: str) -> List[str]:
    with open(filename) as f:
        return [_.strip() for _ in f.readlines()]


def generate_file(filename: str, vars_as_list: List[str]):
    outfilename = filename.replace(".template", "")
    print(f"Writing {outfilename}")
    with open(outfilename, "w") as f:
        f.writelines([f"{_}\n" for _ in vars_as_list + read_text_file(filename)])


def scan_files(filelist: List[str], vars: Dict[str, str]):
    vars_as_list = sorted([f"{k}={v}" for k, v in vars.items()], key=lambda x: x.upper())
    for file in filelist:
        if file.endswith(".template"):
            generate_file(file, vars_as_list)


args = parse_args()

vars = {**read_definitions(args.vars), **convert_to_dict(args.v)}
scan_files(read_text_file(args.envfiles), vars)

print("**NOTE** - You may need to restart any frontend/backend server!")
