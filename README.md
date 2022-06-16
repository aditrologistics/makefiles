# Makefile

The makefile is a way to simplify recurring tasks, such as deploying the workload, both frontend and backend.

# Configuration

In the root directory (i.e. the one above where you found this file), you should create a file named `makevars.mak`.

In it, some key parameters must be defined.
``` bash
# Important variable! Will be used for a lot of things!
WORKLOAD_NAME=transportpricing

# These needs to be set if anything is to be uploaded to Confluence
#CONFLUENCE_SPACE=<confluence space name>
#CONFLUENCE_ANCESTOR=Uploaded

# Specify the account numbers for all three environments.
# They ALL need to be defined!!
# If e.g. TEST has no account, specify XXX
AWS_ACCOUNT_DEV=[aws_account_number]
AWS_ACCOUNT_TEST=[aws_account_number]
AWS_ACCOUNT_PROD=[aws_account_number]

# Override possibilites
# AWS_REGION defaults to eu-north-1 if not set
# This is where the workload will be deployed
AWS_REGION=us-east-2

# SSO_ROLE is the name of the permission set used for deploying the workload.
# Default is ALAB-Developer
SSO_ROLE=AWSAdministratorAccess
```

Note that there are some values that will not be available until you have ran `make deploy_backend`!

There is another, optional, file, named `$\makevars.<username>.mak` (The username is found as `echo %USERNAME%` in windows).

It should contain user specific information.
```
CONFLUENCE_USER=<confluence user name, typically your email address>
CONFLUENCE_API_KEY=XXX
```
The confluence related variables are required if you want to publish any documentation to confluence.

# Initialization

## Initialize submodules
This repository is linked to the application repository as a git submodule. To make that work you need to do two things.

```
git submodule init
git submodule update
```

You will need to run `git submodule update` every time the submodule `makefiles` (or any submodule, really) have been updated.

## Make environment
There are some tools you'll need to install. This is handled by a special target.

``` bash
make prereqs
```

will download the tools required **and** install some python scripts. Make sure you are in a virtual environment prior to executing the target!

## AWS credentials

Run the following targets:
```
make ssoconfigure credentials DEPLOYSTAGE=[DEV|TEST|PROD]
```

The first target, `ssoconfigure`, will set up sso logins in aws. Pay attention to the output on the screen, as you need to fill some information during the config process.

You'll need to rerun `make credentials` when the tokens have expired to get a fresh set new token.

You can read more here:

* https://aws.amazon.com/premiumsupport/knowledge-center/sso-temporary-credentials/
* https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html#sso-configure-profile

## Bootstrapping CDK

First time you deploy on an account you need to `make cdk_bootstrap DEPLOYSTAGE=[DEV|TEST|PROD]`.


# Deployment

Make knows (by means of `makevars.mak` and name magic) almost everything it needs to deploy things. The only extra thing you need to supply is the `DEPLOYSTAGE`.

## Deploy backend
``` bash
make deploy_backend DEPLOYSTAGE=[DEV|TEST|PROD]
```

## Deploy frontend
``` bash
make deploy_frontend DEPLOYSTAGE=[DEV|TEST|PROD]
```

## Destroy stack
``` bash
make cdk_destroy DEPLOYSTAGE=[DEV|TEST|PROD]
```

# Local servers

## Frontend

The frontend can be started by `make serve_frontend`.
## Running local backend

In order to make local backend play nicely with your "true" backend resources, you need to set the environment variable `AWS_PROFILE` to the name of the profile you just deployed to. This is typically `<workload>-<stage>`.

By default, when running `make credentials` there are two helper files generated in `.stage:

* `.stage\awsvars.bat`
* `.stage\awsvars.ps1`

They contain scripts to set the environment variables, so you can run `.stage\.awsvars.bat` in cmd or `.stage\awsvars.ps1` in PowerShell prior to starting uvicorn.

## Starting from makefile

`make serve_backend` will start uvicorn with the AWS_PROFILE variable set.

## How to do it manually:
### CMD
In cmd, simply `set AWS_PROFILE=<workload>-<stage>`.

### Powershell

Powershell sets environment variables like this: `$Env:AWS_PROFILE = "<workload>-<stage>"`.

## Reaching backend resources

Typically there are a number of `.env` or `.env.production` files lingering in the file tree. These little fellows contain variables that are used by the python code when running locally or are backed into the frontend when starting the server (or building the production code).

To avoid having to maintain the variables, you simply create a `.env[.*].template` file in a directory. There are scripts running when you do `make backend_deploy` that extracts information from the stack, traverses the file tree and for each `.env[.*].template` file generates a `.env[.*]` file. This is done in such a way that all stack variables (which are put there manually or by the various constructs) extracted and sorted alphabetically, **prepended** to the *.template file and written to the corresponding `.env` file.

Since dotenv (both in python and javascript) can do token replacement, you can build new variables using bits and pieces from the stack. If you have a template file that looks like
```
#===
API_STAGE=prod

VUE_APP_HOST=https://$api_id.execute-api.$REGION.amazonaws.com/$API_STAGE
VUE_APP_WEBSOCKETAPI=wss://$wsapi_id.execute-api.$REGION.amazonaws.com/$STAGE
```

You will end up with an .env-file that looks something like
```
CDNUrl=<id>.cloudfront.net
CDN_ID=<id>
COMPUTED_DATA_DIR=computed_data
CUSTOMER_TABLE=customerdb-customers
ADDRESS_TABLE=customerdb-adresses
SETTINGS_TABLE=customerdb-settingstable
STAGE=TEST
SUMMARIES_TABLE=customerdb-summaries
UPLOADED_DATA_DIR=uploaded_data
UPLOAD_TABLE=customerdb-uploadtable
USER=jesper.hog
UVICORN_PORT=8000
webcontent=transportpricing-webcontent-test
#===
API_STAGE=prod

VUE_APP_HOST=https://$api_id.execute-api.$REGION.amazonaws.com/$API_STAGE
VUE_APP_WEBSOCKETAPI=wss://$wsapi_id.execute-api.$REGION.amazonaws.com/$STAGE
```

As you can see there are several lines added **to the beginning** of the .env-file.

If you have added a new empty .template file and need to generate the .env-file, simply run `make update_env_vars DEPLOYSTAGE=...`.

# When credentials no longer work

If you get a warning similar to
```
current credentials could not be used to assume 'arn:aws:iam::XXXXXXXXXXXX:role/cdk-hnb659fds-lookup-role-XXXXXXXXXXXX-us-east-2', but are for the right account. Proceeding anyway.
```
 The most likely reason is that your tokens have expired. Simply invoke `make credentials` to refresh them and start again. It is of course possible to do `make credentials deploy_backend` in one go. Remember to include `DEPLOYSTAGE=<something>` if you are not working on DEV.