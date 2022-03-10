import configparser
import os
import json
import argparse

ssocache = f"{os.environ['USERPROFILE']}/.aws/sso/cache/8d64733642e7e4ef9e1a8db02112e1aaf495f21c.json"
aws_credentials = f"{os.environ['USERPROFILE']}/.aws/credentials"


def define_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ssofile", required=True, metavar="FILE", help="json file with recent credentials.")
    parser.add_argument("--profile", required=True, metavar="PROFILE", help="Profile to update.")

    return parser.parse_args()


def get_sso_data(ssofile):
    return json.load(open(ssofile))


def update_credentials(profile, credentials, credentialsfile):
    cfg = configparser.ConfigParser()
    cfg.read(credentialsfile)
    if not cfg.has_section(profile):
        cfg.add_section(profile)
    cfg[profile]["aws_access_key_id"] = credentials["roleCredentials"]["accessKeyId"]
    cfg[profile]["aws_secret_access_key"] = credentials["roleCredentials"]["secretAccessKey"]
    cfg[profile]["aws_session_token"] = credentials["roleCredentials"]["sessionToken"]
    with open(credentialsfile, "w") as f:
        cfg.write(f)

args = define_args()
update_credentials(args.profile, get_sso_data(args.ssofile), aws_credentials)
