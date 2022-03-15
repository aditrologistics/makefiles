.PHONY: deploycdk deployfrontend

SSO_PORTAL=https://aditrologistics.awsapps.com/start
SSO_REGION=eu-north-1
# $(if $(DEBUG),,.SILENT:)
thisfile:=$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
makedir=$(dir $(thisfile))
include $(makedir)/makehelpers.mak
include ./makevars.mak
include ./makevars.$(USERNAME).mak
SSO_ROLE?=ALAB-Developer
AWS_REGION?=eu-north-1
DEPLOYSTAGE?=$(if $(DEPLOY),$(DEPLOY),DEV)

STAGE_POSTFIX_DEV=dev
STAGE_POSTFIX_TEST=test
STAGE_POSTFIX_PROD=

AWS_PROFILE_DEV=$(WORKLOAD_NAME)-dev
AWS_PROFILE_TEST=$(WORKLOAD_NAME)-test
AWS_PROFILE_PROD=$(WORKLOAD_NAME)-prod

SUBDOMAIN_DEV=$(WORKLOAD_NAME)-dev
SUBDOMAIN_TEST=$(WORKLOAD_NAME)-test
SUBDOMAIN_PROD=$(WORKLOAD_NAME)

ANCESTOR=$(if $(CONFLUENCE_ANCESTOR),-a $(CONFLUENCE_ANCESTOR))

AWS_ACCOUNT=$(AWS_ACCOUNT_$(DEPLOYSTAGE))
AWS_PROFILE=$(AWS_PROFILE_$(DEPLOYSTAGE))

SUBDOMAIN=$(SUBDOMAIN_$(DEPLOYSTAGE))
HOSTED_ZONE=$(HOSTED_ZONE_$(DEPLOYSTAGE))
CLOUDFRONT_ID=$(CLOUDFRONT_ID_$(DEPLOYSTAGE))

CONFLUENCE_ORGANIZATION=aditrologistics

STAGEDIR=.stage
JQ=$(STAGEDIR)/jq.exe
MD2CONF=$(STAGEDIR)/md_to_conf/md2conf.py
AWS_TOKENS=$(STAGEDIR)/.aws.tokens
AWS_TOKENVARS=$(STAGEDIR)/.aws.tokenvars
UPLOADMARKDOWN=$(MD2CONF) --nogo --markdownsrc bitbucket

ifeq ("$(DEPLOYSTAGE)","PROD")
WEB_BUCKET_NAME=$(WORKLOAD_NAME)-webcontent
endif
ifeq ("$(DEPLOYSTAGE)","DEV")
WEB_BUCKET_NAME=$(WORKLOAD_NAME)-webcontent-dev-$(subst .,-,$(USERNAME))
endif
ifeq ("$(DEPLOYSTAGE)","TEST")
WEB_BUCKET_NAME=$(WORKLOAD_NAME)-webcontent-test
endif

$(warning Deployment stage: $(DEPLOYSTAGE))
cdk_ctx_hosted_zone=$(if $(HOSTED_ZONE),-c hosted_zone=$(HOSTED_ZONE))

cdk_verbosity = $(if $(DEBUG),-vv)

cdk_context=$(cdk_ctx_hosted_zone) \
		-c STAGE=$(DEPLOYSTAGE) \
		-c AWS_ACCOUNT=$(AWS_ACCOUNT) \
		-c SUBDOMAIN=$(SUBDOMAIN) \
		-c WORKLOAD=$(WORKLOAD_NAME) \
		-c REGION=$(AWS_REGION)

deploy_backend backend_deploy backend: cdk_deploy update_env_vars

cdk_deploy:
	cd backend && \
	cdk deploy $(cdk_verbosity) \
		--profile $(AWS_PROFILE) \
		$(cdk_context)


cdk_bootstrap:
	cd backend && \
	cdk bootstrap $(cdk_verbosity) \
		--profile $(AWS_PROFILE) \
		$(cdk_context)


cdk_destroy backend_destroy destroy destroy_backend:
	cd backend && \
	cdk destroy $(cdk_verbosity) \
		--profile $(AWS_PROFILE) \
		$(cdk_context)

build_dist:
	cd frontend && \
	npm run build

deploy_s3:
	$(call require,WEB_BUCKET_NAME,$@)
	aws s3 cp \
		--profile $(AWS_PROFILE) \
		frontend/dist s3://${WEB_BUCKET_NAME} --recursive

# Note: This assumes there is only one distribution!
# When that assumption breaks down, some filtering has to be done
# to find the correct one.
CLOUDFRONT_ID=$(shell aws cloudfront list-distributions \
		--profile $(AWS_PROFILE) \
		| $(JQ) '.DistributionList.Items[0].Id' \
		| sed -e 's/"//g')

invalidate_cdn:
	$(call require,CLOUDFRONT_ID,$@)
	aws cloudfront create-invalidation \
		--profile $(AWS_PROFILE) \
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
	python $(MD2CONF) \
		--nogo \
		--markdownsrc bitbucket \
		-u $(CONFLUENCE_USER) \
		-p $(CONFLUENCE_API_KEY) \
		-o $(CONFLUENCE_ORGANIZATION) \
		$(ANCESTOR) \
		$(sourcefile) $(CONFLUENCE_SPACE)


test: $(STAGEDIR)
	which cdk
	# echo $(shell ls ~/.aws/sso/cache)
	echo "$(shell ls /c)"
	echo $(HOMEDIR)

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
		--profile $(AWS_PROFILE)


ensure_profiles:
	python $(makedir)/utils/ensure_profiles.py \
		--workload $(WORKLOAD_NAME) \
		--region $(AWS_REGION) \
		--ssostarturl $(SSO_PORTAL) \
		--ssoregion $(SSO_REGION) \
		--ssorole $(SSO_ROLE) \
		--stages dev test prod \
		--accounts $(AWS_ACCOUNT_DEV) $(AWS_ACCOUNT_TEST) $(AWS_ACCOUNT_PROD)


ssologin: ensure_profiles
	aws sso login --profile $(AWS_PROFILE)

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


.PHONY: $(STACKVARS) $(DOTENVFILES)

$(DOTENVFILES):
	/usr/bin/find -iname ".env*" \
		-not -type d \
		-not -path "*/node_modules/*" \
		-not -path "*/.env/*" \
		-not -path "*/cdk.out/*" \
		> $@

ENV_UPDATER=python $(makedir)/utils/env_updater.py
update_env_vars: $(STACKVARS) $(DOTENVFILES)
	$(ENV_UPDATER) \
		--vars $(filter %.json,$^) \
		--envfiles $(filter %.txt,$^) \
		-v UVICORN_PORT=8000 \
		-v REGION=$(AWS_REGION)



$(STACKVARS) getoutputs: $(JQ)
	aws --profile $(AWS_PROFILE) cloudformation describe-stacks \
		--stack-name $(WORKLOAD_NAME) \
		| $(JQ) '.Stacks[0].Outputs|map(.OutputValue)' \
		> $(STACKVARS)

# .stage/jq.exe '.StackSummaries|map(select(.StackName == "transportpricing"))[0]'
# .stage/jq.exe '.StackSummaries|map(select(.StackName == "transportpricing")[0]'