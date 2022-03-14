.PHONY: deploycdk deployfrontend

SSO_PORTAL=https://aditrologistics.awsapps.com/start
SSO_REGION=eu-north-1
# $(if $(DEBUG),,.SILENT:)
thisfile:=$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
makedir=$(dir $(thisfile))
include $(makedir)/makehelpers.mak
include ./makevars
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
WEB_BUCKET_NAME=$(WORKLOAD_NAME)-webcontent-dev-$(USERNAME)
endif
ifeq ("$(DEPLOYSTAGE)","TEST")
WEB_BUCKET_NAME=$(WORKLOAD_NAME)-webcontent-test-$(USERNAME)
endif

$(warning Deployment stage: $(DEPLOYSTAGE))
cdk_ctx_hosted_zone=$(if $(HOSTED_ZONE),-c hosted_zone=$(HOSTED_ZONE))

cdk_verbosity = $(if $(DEBUG),-vv)
backend_deploy:
	cd backend && \
	cdk deploy $(cdk_verbosity) \
		--profile $(AWS_PROFILE) \
		$(cdk_ctx_hosted_zone) \
		-c STAGE=$(DEPLOYSTAGE) \
		-c AWS_ACCOUNT=$(AWS_ACCOUNT) \
		-c SUBDOMAIN=$(SUBDOMAIN) \
		-c WORKLOAD=$(WORKLOAD_NAME) \
		-c REGION=$(AWS_REGION)

cdk_bootstrap:
	cd backend && \
	cdk bootstrap $(cdk_verbosity) \
		--profile $(AWS_PROFILE)


build_dist:
	cd frontend && \
	npm run build

deploy_s3:
	$(call require,WEB_BUCKET_NAME,$@)
	aws s3 cp frontend/dist s3://${WEB_BUCKET_NAME} --recursive --profile $(AWS_PROFILE)

invalidate_cdn:
	$(call require,CLOUDFRONT_ID,$@)
	aws cloudfront create-invalidation \
		--profile $(AWS_PROFILE) \
		--distribution-id ${CLOUDFRONT_ID} \
		--paths /index.html

frontend_deploy: build_dist deploy_s3 invalidate_cdn

docs: prereqs
	$(call require,CONFLUENCE_SPACE)
	$(MD2CONF) README.md $(CONFLUENCE_SPACE) \
		--nogo \
		--markdownsrc bitbucket \
		$(ANCESTOR)


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

getoutputs: $(JQ)
	# aws --profile $(AWS_PROFILE) cloudformation list-stacks \
	# 	--no-paginate \
	# 	--stack-status-filter UPDATE_COMPLETE \
	# 	| $(JQ) '.StackSummaries|map(select(.StackName == "$(WORKLOAD_NAME)"))[0].StackId'
	aws --profile $(AWS_PROFILE) cloudformation describe-stacks \
		--stack-name $(WORKLOAD_NAME) \
		| $(JQ) '.Stacks[0].Outputs|map(.OutputKey+"="+.OutputValue)' \
		> $(STAGEDIR)/$(WORKLOAD_NAME)_outputs.json

# .stage/jq.exe '.StackSummaries|map(select(.StackName == "transportpricing"))[0]'
# .stage/jq.exe '.StackSummaries|map(select(.StackName == "transportpricing")[0]'