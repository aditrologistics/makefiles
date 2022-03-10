import configparser
import os
import argparse
from typing import List

aws_config = f"{os.environ['USERPROFILE']}/.aws/config"


def define_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", metavar="REGION", help="Region for workload.", default="us-east-2")
    parser.add_argument("--workload", required=True, metavar="NAME", help="Name of workload.")
    parser.add_argument("--ssostarturl", required=True, metavar="NAME", help="Start URL for SSO.")
    parser.add_argument("--ssoregion", required=True, metavar="NAME", help="Region for SSO.")
    parser.add_argument("--ssorole", required=True, metavar="NAME", help="Login role for SSO.")
    parser.add_argument("--stages", required=True,  nargs='+', metavar="STAGE", help="Stages to configure.")
    parser.add_argument("--accounts", required=True,  nargs='+', metavar="ACCOUNT", help="Accounts for the different stages..")

    return parser.parse_args()


def ensure_profiles(
        configfile: str,
        *,
        region: str,
        workload: str,
        ssostarturl: str,
        ssoregion: str,
        ssorolename: str,
        stages: List[str],
        accounts: List[str]):
    cfg = configparser.ConfigParser()
    cfg.read(configfile)
    for i, stage in enumerate(stages):
        profile = f"{workload}-{stage.lower()}"
        section = f"profile {profile}"
        if not cfg.has_section(section):
            print(f"Added profile {profile}.")
            cfg.add_section(section)

        print(f"Ensuring settings for {profile}")
        cfg[section]["region"] = region
        cfg[section]["sso_start_url"] = ssostarturl
        cfg[section]["sso_region"] = ssoregion
        cfg[section]["sso_role_name"] = ssorolename
        cfg[section]["output"] = "json"
        cfg[section]["sso_account_id"] = accounts[i]

    with open(configfile, "w") as f:
        cfg.write(f)


args = define_args()
ensure_profiles(
    aws_config,
    region=args.region,
    workload=args.workload,
    ssostarturl=args.ssostarturl,
    ssoregion=args.ssoregion,
    ssorolename=args.ssorole,
    stages=args.stages,
    accounts=args.accounts)
