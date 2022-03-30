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
    parser.add_argument("--bat", required=False, metavar="FILE", help="Batchfile to set env vars/CMD.")
    parser.add_argument("--ps", required=False, metavar="FILE", help="Batchfile to set env vars/Powershell.")

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


def create_batch_file(profile, batchfile):
    with open(batchfile, "w") as f:
        f.write(f"SET AWS_PROFILE={profile}\n")


def create_ps_file(profile, batchfile):
    with open(batchfile, "w") as f:
        f.write(f'$Env:AWS_PROFILE = "{profile}"\n')


args = define_args()
credentials = get_sso_data(args.ssofile)
update_credentials(args.profile, credentials, aws_credentials)
if args.bat:
    create_batch_file(args.profile, args.bat)
if args.ps:
    create_ps_file(args.profile, args.ps)
