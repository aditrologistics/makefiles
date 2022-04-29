import argparse
import json
from typing import Dict, List
import logging
import sys


def setup_logger(name: str = None, level: int = logging.DEBUG) -> logging.Logger:
    logger = logging.getLogger(name)
    if any([_.name == name for _ in logger.handlers]):
        logger.debug(f"Handler {name} already initialized")
        return logger

    logger.setLevel(level)
    handler = logging.StreamHandler(sys.stderr)
    handler.name = name
    handler.setLevel(level)
    formatter = logging.Formatter('%(asctime)s | %(levelname)-8s | %(message)s')
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    logger.propagate = False  # Prevent duplicate loglines in cloud watch
    return logger


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser("Update .env-files")
    parser.add_argument('--vars', type=str, required=True)
    parser.add_argument('--envfiles', type=str, required=True)
    parser.add_argument('-v', action='append', type=str, required=False)
    return parser.parse_args()


def convert_to_dict(vars: List[str]) -> Dict[str, str]:
    """
    Converts a list of strings with the format <value>=<key>
    to a dictionary {<value>: <key>, ...}

    Args:
        vars (List[str]): Incoming list

    Returns:
        Dict[str, str]: Resulting dictionary
    """
    result = {}
    for _ in vars or []:
        pair = _.split("=", 2)
        if len(pair) != 2:
            logger.info(f"Unable to parse '{_}'")
            continue
        previous_value = result.get(pair[0])
        if previous_value:
            if previous_value != pair[1]:
                logger.warning(f"Redefining {pair[0]} from '{previous_value}' to '{pair[1]}'.")
            else:
                logger.debug(f"{pair[0]} defined twice to '{pair[1]}'.")

        result[pair[0]] = pair[1]

    return result


def read_definitions(filename: str) -> Dict[str, str]:
    """
    Reads a json formatted list of strings and converts it to a dictionary.

    Args:
        filename (str): Filename to read.

    Returns:
        Dict[str, str]: Resulting dictionary.
    """
    logger.info(f"Opening {filename}")
    try:
        with open(filename) as f:
            data = json.load(f)
        return convert_to_dict(data)
    except json.decoder.JSONDecodeError:
        logger.error("Unable to parse data!")
        raise


def read_text_file(filename: str) -> List[str]:
    with open(filename) as f:
        return [_.strip() for _ in f.readlines()]


def generate_file(filename: str, vars_as_list: List[str]):
    outfilename = filename.replace(".template", "")
    logger.info(f"Writing {outfilename}")
    with open(outfilename, "w") as f:
        f.writelines([f"{_}\n" for _ in vars_as_list + read_text_file(filename)])


def scan_files(filelist: List[str], vars: Dict[str, str]):
    vars_as_list = sorted([f"{k}={v}" for k, v in vars.items()], key=lambda x: x.upper())
    for file in filelist:
        if file.endswith(".template"):
            generate_file(file, vars_as_list)


logger = setup_logger(name="env_updater")
args = parse_args()

vars = {**read_definitions(args.vars), **convert_to_dict(args.v)}
scan_files(read_text_file(args.envfiles), vars)

logger.warning("**NOTE** - You may need to restart any frontend/backend server!")
