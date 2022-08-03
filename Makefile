.PHONY: deploycdk deployfrontend

# $(if $(DEBUG),,.SILENT:)
thisfile:=$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
makedir=$(dir $(thisfile))
include $(makedir)/makehelpers.mak
include ./makevars.mak
-include ./makevars.$(USERNAME).mak

ifdef DEPLOY_STAGE
$(error Do not define DEPLOY_STAGE. The correct variable is DEPLOYSTAGE)
endif
ifdef deploystage
$(error Do not define deploystage. The correct variable is DEPLOYSTAGE)
endif
ifdef deploy_stage
$(error Do not define deploy_stage. The correct variable is DEPLOYSTAGE)
endif

# Unless we're executing the target `check`
# verify that HOMEDRIVE is set to C:
# If it is not, the aws/cdk tools will not find
# credentials and config.
# This is used to fail fast.
ifneq ($(MAKECMDGOALS),check)
EXPECTED_HOMEDRIVE?=C:
$(if $(subst $(EXPECTED_HOMEDRIVE),,$(HOMEDRIVE)),\
	$(error Run `make check` - HOMEDRIVE is set to "$(HOMEDRIVE)",\
			expected "$(EXPECTED_HOMEDRIVE)"))
endif

ORGANIZATION?=aditrologistics
ROOT_DOMAIN_NAME?=$(ORGANIZATION)
AWS_ORGANIZATION?=$(ORGANIZATION)
GIT_ORGANIZATION?=$(ORGANIZATION)
CONFLUENCE_ORGANIZATION=$(ORGANIZATION)

SSO_PORTAL=https://$(AWS_ORGANIZATION).awsapps.com/start
SSO_REGION=eu-north-1
SSO_ROLE?=ALAB-Developer
AWS_REGION?=eu-north-1
DEPLOYSTAGE?=$(if $(DEPLOY),$(DEPLOY),DEV)

# The profiles are named as <workload>-<stage>
AWS_PROFILE_DEV=$(WORKLOAD_NAME)-dev
AWS_PROFILE_TEST=$(WORKLOAD_NAME)-test
AWS_PROFILE_PROD=$(WORKLOAD_NAME)-prod
AWS_PROFILE=$(AWS_PROFILE_$(DEPLOYSTAGE))

# Domains are named <workload>-<stage> except PROD which has no postfix.
# Note that these variables can be set in the project-specific makevars.mak
DOMAIN_NAME?=$(WORKLOAD_NAME)
SUBDOMAIN_DEV?=$(DOMAIN_NAME)-dev
SUBDOMAIN_TEST?=$(DOMAIN_NAME)-test
SUBDOMAIN_PROD?=$(DOMAIN_NAME)
SUBDOMAIN=$(SUBDOMAIN_$(DEPLOYSTAGE))
TOP_LEVEL_DOMAIN?=nu
ROOT_DOMAIN?=$(ROOT_DOMAIN_NAME).$(TOP_LEVEL_DOMAIN)

AWS_ACCOUNT=$(AWS_ACCOUNT_$(DEPLOYSTAGE))

ANCESTOR=$(if $(CONFLUENCE_ANCESTOR),-a $(CONFLUENCE_ANCESTOR))

STAGEDIR=.stage
JQ=$(STAGEDIR)/jq.exe
cdk_verbosity = $(if $(DEBUG),-vv)
CDK=cdk --profile $(AWS_PROFILE) $(cdk_verbosity)
AWS=aws --profile $(AWS_PROFILE)
ECHO=@echo
MD2CONF=$(STAGEDIR)/md_to_conf/md2conf.py
AWS_TOKENS=$(STAGEDIR)/.aws.tokens
AWS_TOKENVARS=$(STAGEDIR)/.aws.tokenvars
UPLOADMARKDOWN=python $(MD2CONF) --nogo --markdownsrc bitbucket
ENV_UPDATER=python $(makedir)/utils/env_updater.py

DEFINED_STAGES=$(if $(AWS_ACCOUNT_DEV),dev) $(if $(AWS_ACCOUNT_TEST),test) $(if $(AWS_ACCOUNT_PROD),prod)

CLEANABLE_FILES=$(STAGEDIR)/.installed.flake8 $(STAGEDIR)/.installed.pytest

# These files need to be included after variables are defined
include $(STAGEDIR)/hosted-zone.$(DEPLOYSTAGE).mak
-include $(STAGEDIR)/cloudfront-id.$(DEPLOYSTAGE).mak

# Write a warning if DEPLOYSTAGE is different from last invocation.
-include $(STAGEDIR)/laststage.mak

ifdef LASTSTAGE
ifneq "$(LASTSTAGE)" "$(DEPLOYSTAGE)"
$(warning ***)
$(warning *** You changed from $(LASTSTAGE) to $(DEPLOYSTAGE). On purpose?)
$(warning ***)
endif
endif
$(shell echo "LASTSTAGE=$(DEPLOYSTAGE)" > $(STAGEDIR)/laststage.mak)

# Extract hosted zone with the expected name from the account
GETZONEID=$(shell $(AWS) route53 list-hosted-zones-by-name \
		--dns-name=$(SUBDOMAIN).$(ROOT_DOMAIN) \
	| $(JQ) .HostedZones[0].Id \
	| sed -e 's/"//g' -e 's!/hostedzone/!!')

# Note: This assumes there is only one distribution!
# When that assumption breaks down, some filtering has to be done
# to find the correct one.
GETCLOUDFRONTID=$(shell $(AWS) cloudfront list-distributions \
		| $(JQ) '.DistributionList.Items[0].Id' \
		| sed -e 's/"//g')

# This make snippet will be generated when the file is included above
$(STAGEDIR)/hosted-zone.%.mak: $(JQ)
	$(ECHO) Generating $@
	$(ECHO) Fetching hosted zone id...
	$(ECHO) HOSTED_ZONE=$(GETZONEID) > $@

# This make snippet will be generated when the file is included above
$(STAGEDIR)/cloudfront-id.%.mak: $(JQ)
	$(ECHO) Generating $@
	$(ECHO) Fetching cloudfront/distribution id...
	$(ECHO) CLOUDFRONT_ID=$(subst null,,$(GETCLOUDFRONTID)) > $@

# This file will be generated after backend_deploy
# or `make update_env_vars`.
# If it is not available the variable WEB_BUCKET_NAME
# will not be set and it will not be possible to
# deploy frontend.
-include $(STAGEDIR)/.env.webbucket-$(DEPLOYSTAGE).mak

foo:
	$(ECHO) CLOUDFRONT: $(CLOUDFRONT_ID)
	$(ECHO) HOSTED_ZONE: $(HOSTED_ZONE)
	$(ECHO) variables $(subst CDK_,,$(filter CDK_%,$(.VARIABLES)))

clean:
	rm -f $(CLEANABLE_FILES)

$(warning Deployment stage: $(DEPLOYSTAGE))

check check_environment checkenvironment:
	$(ECHO) -e "CDK looks at some environment variables to find configuration files.\n" \
		"These are HOMEDRIVE, HOMEPATH and USERPROFILE.\n" \
		"HOMEPATH is constructed as /Users/%USERNAME%\n" \
		"USERPROFILE is %HOMEDRIVE%%HOMEPATH%\n" \
		"HOMEDRIVE should be C:\n" \
		"Your settings:\n" \
		"- HOMEDRIVE: $(HOMEDRIVE)\n" \
		'- HOMEPATH: $(HOMEPATH)\n' \
		"- USERPROFILE: $(USERPROFILE)\n" \
		"\n" \
		"CMD:\n" \
		"----\n" \
		"SET HOMEDRIVE=C: && SET HOMEPATH=\Users\%USERNAME%  && SET USERPROFILE=c:\Users\%USERNAME%\n" \
		"\n" \
		"PowerShell:\n" \
		"-----------\n" \
		'$$Env:HOMEDRIVE="C:"; $$Env:HOMEPATH="\Users\$(USERNAME)"; $$Env:USERPROFILE="C:\Users\$(USERNAME)"\n'


cdk_context=\
		-c STAGE=$(DEPLOYSTAGE) \
		-c AWS_ACCOUNT=$(AWS_ACCOUNT) \
		-c SUBDOMAIN=$(SUBDOMAIN) \
		-c WORKLOAD=$(WORKLOAD_NAME) \
		-c REGION=$(AWS_REGION) \
		-c hosted_zone=$(HOSTED_ZONE)

deploy_all: deploy_backend deploy_frontend

deploy_backend deploybackend backend_deploy backend: cdk_deploy update_env_vars
destroy backend_destroy destroy_backend: cdk_destroy
bootstrap: cdk_bootstrap
synth: cdk_synth

cdk_extra_action_deploy:
	rm -f $(STACKVARS)

cdk_extra_action_%:
	echo Nothing extra to do for $@

cdk_%: remove_hostedzone_if_empty cdk_extra_action_%
	cd backend && \
	$(CDK) $(subst cdk_,,$@) \
		$(cdk_context)


build_dist:
	cd frontend && \
	npm run build

serve_frontend frontend_server:
	cd frontend && \
	npm run serve

serve_backend backend_server:
	cd backend && \
	AWS_PROFILE=$(AWS_PROFILE) uvicorn \
		--app-dir api \
		--reload api:app \
		--no-use-colors

deploy_s3:
	$(if $(WEB_BUCKET_NAME),,$(warning run "make update_env_vars DEPLOYSTAGE=$(DEPLOYSTAGE)" if WEB_BUCKET_NAME is not defined))
	$(call require,WEB_BUCKET_NAME,$@)
	$(AWS) s3 cp \
		frontend/dist s3://${WEB_BUCKET_NAME} --recursive


# Helper target to remove (and redo next make invocation!)
# the snippet that defines CLOUDFRONT_ID
remove_cloudfront-id_if_empty:
	-$(if $(CLOUDFRONT_ID),,rm $(STAGEDIR)/cloudfront-id.$(DEPLOYSTAGE).mak)

remove_hostedzone_if_empty:
	-$(if $(HOSTED_ZONE),,rm $(STAGEDIR)/hosted-zone.$(DEPLOYSTAGE).mak)


invalidate_cdn: remove_cloudfront-id_if_empty
	$(call require,CLOUDFRONT_ID,$@)
	$(AWS) cloudfront create-invalidation \
		--distribution-id ${CLOUDFRONT_ID} \
		--paths /index.html


deploy_frontend frontend_deploy: build_dist deploy_s3 invalidate_cdn


# By default upload README.md. This can be overridden by
# setting CONFLUENCEFILES to a list of files to upload in makevars.mak.
# Example:
# CONFLUENCEFILES=README.md DEVINFO.md
# Note that all files will be uploaded under the same ancestor.
CONFLUENCEFILES?=README.md

upload_%:
	$(call require,CONFLUENCE_SPACE)
	$(call require,CONFLUENCE_USER)
	$(call require,CONFLUENCE_API_KEY)
	$(UPLOADMARKDOWN) \
		-u $(CONFLUENCE_USER) \
		-p $(CONFLUENCE_API_KEY) \
		-o $(CONFLUENCE_ORGANIZATION) \
		$(ANCESTOR) \
		$(subst upload_,,$@) $(CONFLUENCE_SPACE)

makedocs docs: prereqs $(foreach f,$(CONFLUENCEFILES),upload_$(f))


credentials getcredentials: $(JQ) ssologin
	# https://aws.amazon.com/premiumsupport/knowledge-center/sso-temporary-credentials/
	# https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html#sso-configure-profile


	aws sso get-role-credentials \
		--account-id $(AWS_ACCOUNT) \
		--role-name $(SSO_ROLE) \
		--access-token $(shell $(JQ) -r .accessToken $(subst \\\\c\\\\,c:\\\\,$(subst /,\\\\,$(shell ls -t $(HOMEDIR)/.aws/sso/cache/*.json| head -1)))) \
		--region $(SSO_REGION)  > $(AWS_TOKENS)

	python $(makedir)/utils/credentials_updater.py \
		--ssofile $(AWS_TOKENS) \
		--profile $(AWS_PROFILE) \
		--bat $(STAGEDIR)/awsvars.bat \
		--ps $(STAGEDIR)/awsvars.ps1 \


ensure_profiles:
	python $(makedir)/utils/ensure_profiles.py \
		--workload $(WORKLOAD_NAME) \
		--region $(AWS_REGION) \
		--ssostarturl $(SSO_PORTAL) \
		--ssoregion $(SSO_REGION) \
		--ssorole $(SSO_ROLE) \
		--stages $(DEFINED_STAGES) \
		--accounts $(AWS_ACCOUNT_DEV) $(AWS_ACCOUNT_TEST) $(AWS_ACCOUNT_PROD)


ssologin: ensure_profiles
	$(AWS) sso login


ssosetup ssoconfigure ssoconfig:
	@echo -e "\n\n"
	@echo "Useful values"
	@echo "============="
	@echo "SSO Start URL: $(SSO_PORTAL)"
	@echo "SSO Region: $(SSO_REGION)"
	@echo "Name the profile: $(AWS_PROFILE)"
	@echo -e "\n\n"
	aws configure sso


$(JQ):
	$(call require,JQ)
	$(MKTARGETDIR)
	curl https://github.com/stedolan/jq/releases/download/jq-1.6/jq-win64.exe -L -o $@


$(STAGEDIR)/.installed.md2conf: $(MD2CONF)
	$(call require,MD2CONF)
	pip install -r $(dir $(MD2CONF))requirements.txt
	touch $@


$(MD2CONF):
	$(call require,MD2CONF)
	git clone https://github.com/aditrologistics/md_to_conf.git $(dir $@)


$(STAGEDIR):
	mkdir $@


prereqs: $(STAGEDIR) $(JQ) $(STAGEDIR)/.installed.md2conf

STACKVARS=$(STAGEDIR)/$(WORKLOAD_NAME)-$(DEPLOYSTAGE)_outputs.json
DOTENVFILES=$(STAGEDIR)/$(WORKLOAD_NAME)-$(DEPLOYSTAGE)_dotenvs.txt
WEBBUCKET_MAK=$(STAGEDIR)/.env.webbucket_all.mak.template

# Always redo these files
.PHONY: $(DOTENVFILES) $(WEBBUCKET_MAK)


# This recipe simply empties the target file
$(WEBBUCKET_MAK):
	echo > $@


$(DOTENVFILES): $(WEBBUCKET_MAK)
	/usr/bin/find -iname ".env*" \
		-not -type d \
		-not -path "*/node_modules/*" \
		-not -path "*/.env/*" \
		-not -path "*/cdk.out/*" \
		> $@


# Trying to make as few assumptions as possible, but still need to get the name of the variable
# containing the name of the web deployment bucket. It is assumed to be 'webcontent' as per the
# CDK construct Website and will be remapped to WEB_BUCKET_NAME
# If the name is different, pass it as a parameter.
WEB_BUCKET_NAME_S3?=webcontent

update_env_vars: $(STACKVARS) $(DOTENVFILES) $(WEBBUCKET_MAK)
	$(ENV_UPDATER) \
		--vars $(filter %.json,$^) \
		--envfiles $(filter %.txt,$^) \
		-v UVICORN_PORT=8000 \
		-v REGION=$(AWS_REGION) \
		-v AWS_PROFILE=$(AWS_PROFILE) \
		$(foreach ev,$(EXTRA_ENV_VARS),-v $(ev))

	grep "^$(WEB_BUCKET_NAME_S3)=" $(subst .template,,$(WEBBUCKET_MAK)) \
		| sed -e "s/$(WEB_BUCKET_NAME_S3)/WEB_BUCKET_NAME/" \
		> $(subst _all.mak.template,-$(DEPLOYSTAGE).mak,$(WEBBUCKET_MAK))


$(STACKVARS) getoutputs: $(JQ)
	$(AWS) cloudformation describe-stacks \
		--stack-name $(WORKLOAD_NAME) \
		| $(JQ) '.Stacks[0].Outputs|map(.OutputValue)' \
		> $(STACKVARS)

refresh_make:
	cd $(makedir) && \
		git checkout main && \
		git pull

	git add $(makedir)
	$(ECHO) "makefiles added for next commit"


flake_setup: $(STAGEDIR)/.upgrade.pip $(STAGEDIR)/.installed.flake8 $(STAGEDIR)/.requirements.installed
pytest_setup: $(STAGEDIR)/.upgrade.pip $(STAGEDIR)/.installed.pytest $(STAGEDIR)/.requirements.installed

$(STAGEDIR)/.installed.%:
	pip install $(subst .,,$(suffix $@))
	$(ECHO) "$(subst .,,$(suffix $@)) installed" | tee $@

CLEANABLE_FILES+=$(STAGEDIR)/.upgrade.pip
$(STAGEDIR)/.upgrade.pip:
	python -m pip install --upgrade pip
	$(ECHO) "pip upgraded" | tee $@

CLEANABLE_FILES+=$(STAGEDIR)/.requirements.installed
$(STAGEDIR)/.requirements.installed: requirements.txt
	if [ -f $< ]; then TOKEN=$(TOKEN)@ pip install -r $<; fi
	$(ECHO) "$< installed" | tee $@

# This target is used by github action
pytest: pytest_setup
	AWS_PROFILE=$(AWS_PROFILE) pytest

# This target is used by github action
flake: flake_setup
	# stop the build if there are Python syntax errors or undefined names
	flake8 --count --select=E9,F63,F7,F82 --show-source --statistics
	# exit-zero treats all errors as warnings. The GitHub editor is 127 chars wide
	flake8 --count --max-complexity=10 --statistics backend

GIT_ACTION_REPO_NAME?=github_actions
GIT_ACTION_REPO?=http://github.com/$(if $(GIT_ORGANIZATION),$(GIT_ORGANIZATION)/,)$(GIT_ACTION_REPO_NAME).git
ACTIONS?=flake8 pytest
WORKFLOW_DIR=.github/workflows

$(STAGEDIR)/$(GIT_ACTION_REPO_NAME):
	git clone $(GIT_ACTION_REPO) $@

actions init_actions: $(STAGEDIR)/$(GIT_ACTION_REPO_NAME)
	mkdir -p $(WORKFLOW_DIR)
	cd $(STAGEDIR)/$(GIT_ACTION_REPO_NAME) && git pull
	cp \
		$(foreach f,$(ACTIONS),$(STAGEDIR)/$(GIT_ACTION_REPO_NAME)/workflows/$(f).yaml) \
		$(WORKFLOW_DIR)
	git status


PROTECTED_BRANCHES?=main master releases release dev
purge_branches:
	git branch | grep -q "^\* main" || (echo "Not on main branch"; exit 1)
	git branch --merged \
		| grep -v $(foreach b,$(PROTECTED_BRANCHES),-e $(b)) \
		| xargs -I {} git branch -d {}
