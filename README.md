# Makefile

The makefile is a way to simplify recurring tasks, such as deploying the workload, both frontend and backend.

# Configuration

In the root directory (i.e. the one above where you found this file), you should create a file named `makevars`.

In it, some key parameters must be defined.
``` bash
# Important variable! Will be used for a lot of things!
WORKLOAD_NAME=transportpricing

# These needs to be set if anything is to be uploaded to Confluence
#CONFLUENCE_SPACE=~383862944
#CONFLUENCE_ANCESTOR=Uploaded

# Specify the account numbers for all three environments.
# They ALL need to be defined!!
# If e.g. TEST has no account, specify XXX
AWS_ACCOUNT_DEV=077410211940
AWS_ACCOUNT_TEST=383105234713
AWS_ACCOUNT_PROD=584748006736

# Specify the id of the Hosted Zone.
# They ALL need to be defined!!
# If e.g. TEST has no account, specify XXX
HOSTED_ZONE_DEV=Z0233749MOQEGRE2N9TX
HOSTED_ZONE_TEST=Z07839311QAC1PUU4ON91
HOSTED_ZONE_PROD=Z02354332J0BS7Y5CNJ0L

# Specify the id of CloudFront distribution.
# It is only available after the CDN has been deployed!
CLOUDFRONT_ID_DEV=E2ZSRX6VJFA0AZ
CLOUDFRONT_ID_TEST=XXX
CLOUDFRONT_ID_PROD=XXX

# Override possibilites
# AWS_REGION defaults to eu-north-1 if not set
# This is where the workload will be deployed
AWS_REGION=us-east-2

# SSO_ROLE is the name of the permission set used for deploying the workload.
# Default is ALA-Developer
SSO_ROLE=AWSAdministratorAccess
```

Note that there are some values that will not be available until you have ran `make deploy_backend`!

There is another, optional, file, named `$\makevars.<username>` (The username is found as `echo %USERNAME%` in windows).

It should contain user specific information.
```
CONFLUENCE_USER=<confluence user name, typically your email address>
CONFLUENCE_API_KEY=XXX
```

# Initialization

## Initialize submodules
This repository is linked to the application repository as a git submodule. To make that work you need to do two things.

```
git submodule init
git submodule update
```

You will need to run `git submodule update` every time `makefiles` have been updated.

## Make environment
Run `make prereqs` to download all the tools you need.

## AWS credentials

First run `make ssoconfigure`. What you need to fill in is printed on screen.

Then run `make credentials DEPLOYSTAGE=[DEV|TEST|PROD]` to get the login tokens you need for the stage you want to dpeloy to.

You'll need to rerun `make credentials` when the tokens have expired to get a fresh set new token.

## Bootstrapping CDK

First time you deploy on an account you need to `make cdk_bootstrap DEPLOYSTAGE=[DEV|TEST|PROD]`.

You can read more here:
* https://aws.amazon.com/premiumsupport/knowledge-center/sso-temporary-credentials/
* https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html#sso-configure-profile


# Deployment

Make knows (by means of `makevars`) almost everything it needs to deploy things. The only extra thing you need to supply is the `DEPLOYSTAGE`.

## Deploy backend
``` bash
make deploy_backend DEPLOYSTAGE=[DEV|TEST|PROD]
```

## Deploy frontend
``` bash
make deploy_backend DEPLOYSTAGE=[DEV|TEST|PROD]
```

## Destroy stack
``` bash
make cdk_destroy DEPLOYSTAGE=[DEV|TEST|PROD]
```

# When credentials no longer work

If you get a warning similar to
```
current credentials could not be used to assume 'arn:aws:iam::XXXXXXXXXXXX:role/cdk-hnb659fds-lookup-role-XXXXXXXXXXXX-us-east-2', but are for the right account. Proceeding anyway.
(To get rid of this warning, please upgrade to bootstrap version >= 8)
current credentials could not be used to assume 'arn:aws:iam::XXXXXXXXXXXX:role/cdk-hnb659fds-deploy-role-XXXXXXXXXXXX-us-east-2', but are for the right account. Proceeding anyway.
```
 The most likely reason is that your tokens have expired. Simply invoke `make credentials` to refresh them and start again. It is of course possible to do `make credentials deploy_backend` in one go.