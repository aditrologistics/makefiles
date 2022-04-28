.PHONY: deploycdk deployfrontend

# $(if $(DEBUG),,.SILENT:)
thisfile:=$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
makedir=$(dir $(thisfile))
include $(makedir)/makehelpers.mak
include ./makevars.mak
-include ./makevars.$(USERNAME).mak

# Unless we're executing the target `check`
# verify that HOMEDRIVE is set to C:
# If it is not, the aws/cdk tools will not find
# credentials and config.
ifneq ($(MAKECMDGOALS),check)
EXPECTED_HOMEDRIVE?=C:
$(if $(subst $(EXPECTED_HOMEDRIVE),,$(HOMEDRIVE)),\
	$(error Run `make check` - HOMEDRIVE is set to "$(HOMEDRIVE)",\
			expected "$(EXPECTED_HOMEDRIVE)"))
endif

SSO_PORTAL=https://aditrologistics.awsapps.com/start
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
SUBDOMAIN_DEV?=$(WORKLOAD_NAME)-dev
SUBDOMAIN_TEST?=$(WORKLOAD_NAME)-test
SUBDOMAIN_PROD?=$(WORKLOAD_NAME)
SUBDOMAIN=$(SUBDOMAIN_$(DEPLOYSTAGE))

AWS_ACCOUNT=$(AWS_ACCOUNT_$(DEPLOYSTAGE))

ANCESTOR=$(if $(CONFLUENCE_ANCESTOR),-a $(CONFLUENCE_ANCESTOR))
CONFLUENCE_ORGANIZATION=aditrologistics

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

# These files need to be included after variables are defined
include $(STAGEDIR)/hosted-zone.$(DEPLOYSTAGE).mak
-include $(STAGEDIR)/cloudfront-id.$(DEPLOYSTAGE).mak

# Extract hosted zone from the account
# assuming there's exactly one - no validation of that assumption right now
GETZONEID=$(shell $(AWS) route53 list-hosted-zones \
	| $(JQ) .HostedZones[0].Id \
	| sed -e 's/"//g' -e 's!/hostedzone/!!')

# Note: This assumes there is only one distribution!
# When that assumption breaks down, some filtering has to be done
# to find the correct one.
GETCLOUDFRONTID=$(shell $(AWS) cloudfront list-distributions \
		| $(JQ) '.DistributionList.Items[0].Id' \
		| sed -e 's/"//g')

# This make snippet will be generated on inclusion above
$(STAGEDIR)/hosted-zone.%.mak: $(JQ)
	$(ECHO) Generating $@
	$(ECHO) Fetching hosted zone id...
	$(ECHO) HOSTED_ZONE=$(GETZONEID) > $@

# This make snippet will be generated on inclusion above
$(STAGEDIR)/cloudfront-id.%.mak: $(JQ)
	$(ECHO) Generating $@
	$(ECHO) Fetching cloudfront/distribution id...
	$(ECHO) CLOUDFRONT_ID=$(subst null,,$(GETCLOUDFRONTID)) > $@

# This file will be generated after backend_deploy
# or `make update_env_vars`.
# If it is not available the variable WEB_BUCKET_NAME
# will not be set and it will not be possible to
# deploy frontend.
-include $(STAGEDIR)/.env.webbucket.mak

foo:
	$(ECHO) CLOUDFRONT: $(CLOUDFRONT_ID)
	$(ECHO) HOSTED_ZONE: $(HOSTED_ZONE)
	$(ECHO) variables $(subst CDK_,,$(filter CDK_%,$(.VARIABLES)))

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
		"SET HOMEDRIVE=C:\n" \
		"SET HOMEPATH=\Users\%USERNAME%\n" \
		"SET USERPROFILE=%HOMEDRIVE%%HOMEPATH%\n" \
		"\n" \
		"PowerShell:\n" \
		"-----------\n" \
		'$$Env:HOMEDRIVE="C:"\n' \
		'$$Env:HOMEPATH="\Users\$(USERNAME)"\n' \
		'$$Env:USERPROFILE="C:\Users\$(USERNAME)"\n'


cdk_context=\
		-c STAGE=$(DEPLOYSTAGE) \
		-c AWS_ACCOUNT=$(AWS_ACCOUNT) \
		-c SUBDOMAIN=$(SUBDOMAIN) \
		-c WORKLOAD=$(WORKLOAD_NAME) \
		-c REGION=$(AWS_REGION) \
		-c hosted_zone=$(HOSTED_ZONE)

deploy_backend deploybackend backend_deploy backend: cdk_deploy update_env_vars
destroy backend_destroy destroy_backend: cdk_destroy
bootstrap: cdk_bootstrap
synth: cdk_synth

cdk_%: remove_hostedzone_if_empty
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


sourcefile=README.md
makedocs: CONFLUENCE_SPACE=LOG
makedocs: CONFLUENCE_ANCESTOR="Creating new workloads"
makedocs: sourcefile=makefiles/README.md
makedocs: docs


docs: prereqs
	$(call require,CONFLUENCE_SPACE)
	$(call require,CONFLUENCE_USER)
	$(call require,CONFLUENCE_API_KEY)
	$(UPLOADMARKDOWN) \
		-u $(CONFLUENCE_USER) \
		-p $(CONFLUENCE_API_KEY) \
		-o $(CONFLUENCE_ORGANIZATION) \
		$(ANCESTOR) \
		$(sourcefile) $(CONFLUENCE_SPACE)


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
	git clone https://github.com/RittmanMead/md_to_conf.git $(dir $@)


$(STAGEDIR):
	mkdir $@


prereqs: $(STAGEDIR) $(JQ) $(STAGEDIR)/.installed.md2conf

STACKVARS=$(STAGEDIR)/$(WORKLOAD_NAME)-$(DEPLOYSTAGE)_outputs.json
DOTENVFILES=$(STAGEDIR)/$(WORKLOAD_NAME)-$(DEPLOYSTAGE)_dotenvs.txt
WEBBUCKET_MAK=$(STAGEDIR)/.env.webbucket_all.mak.template

# Always redo these files
.PHONY: $(STACKVARS) $(DOTENVFILES) $(WEBBUCKET_MAK)


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
		-v REGION=$(AWS_REGION)

	grep "^$(WEB_BUCKET_NAME_S3)=" $(subst .template,,$(WEBBUCKET_MAK)) \
		| sed -e "s/$(WEB_BUCKET_NAME_S3)/WEB_BUCKET_NAME/" \
		> $(subst _all.mak.template,.mak,$(WEBBUCKET_MAK))


$(STACKVARS) getoutputs: $(JQ)
	$(AWS) cloudformation describe-stacks \
		--stack-name $(WORKLOAD_NAME) \
		| $(JQ) '.Stacks[0].Outputs|map(.OutputValue)' \
		> $(STACKVARS)

# empty_bucket:
# 	$(call require,BUCKET_NAME,$@)
# 	$(AWS) s3api list-object-versions \
# 		--bucket $(BUCKET_NAME) \
# 	| $(JQ) ".Versions | [.[] | {Key: Key}]"