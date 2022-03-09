.PHONY: deploycdk deployfrontend

$(if $(DEBUG),,.SILENT:)
include makehelpers.mak
-include makevars

ANCESTOR=$(if $(CONFLUENCE_ANCESTOR),-a $(CONFLUENCE_ANCESTOR))
export DEPLOYSTAGE?=DEV
export AWS_ACCOUNT=$(AWS_ACCOUNT_$(DEPLOYSTAGE))
export AWS_PROFILE=$(AWS_PROFILE_ROOT)_$(DEPLOYSTAGE)
STAGE=.stage
JQ=$(STAGE)/jq.exe
MD2CONF=$(STAGE)/md_to_conf/md2conf.py
AWS_TOKENS=$(STAGE)/.aws.tokens
AWS_TOKENVARS=$(STAGE)/.aws.tokenvars
UPLOADMARKDOWN=$(MD2CONF) --nogo --markdownsrc bitbucket

$(info Deploymanet stage: $(DEPLOYSTAGE))

backend_deploy:
	cd backend && \
	make deploy

frontend_deploy:
	cd frontend && \
	make deploy

docs: prereqs
	$(call require,CONFLUENCE_SPACE)
	$(MD2CONF) README.md $(CONFLUENCE_SPACE) \
		--nogo \
		--markdownsrc bitbucket \
		$(ANCESTOR)


test:
	# echo $(shell ls ~/.aws/sso/cache)
	echo "$(shell ls /c)"
	echo $(HOMEDIR)

getcredentials:
	# https://aws.amazon.com/premiumsupport/knowledge-center/sso-temporary-credentials/
	# https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html#sso-configure-profile


	aws sso get-role-credentials \
		--account-id $(AWS_ACCOUNT) \
		--role-name $(AWS_ROLE) \
		--access-token $(shell $(JQ) -r .accessToken $(subst \\\\c\\\\,c:\\\\,$(subst /,\\\\,$(shell ls -t $(HOMEDIR)/.aws/sso/cache/*.json| head -1)))) \
		--region $(AWS_REGION)  > $(AWS_TOKENS)

	python utils/credentials_updater.py --ssofile $(AWS_TOKENS) --profile bazbar


ssologin:
	aws sso login --profile $(AWS_PROFILE)


$(JQ):
	$(call require,JQ)
	curl https://github.com/stedolan/jq/releases/download/jq-1.6/jq-win64.exe -L -o $@

$(STAGE)/.installed.md2conf: $(MD2CONF)
	$(call require,MD2CONF)
	pip install -r $(dir $(MD2CONF))requirements.txt
	touch $@

$(MD2CONF):
	$(call require,MD2CONF)
	git clone https://github.com/RittmanMead/md_to_conf.git $(dir $@)

$(STAGE):
	mkdir $@

prereqs: $(STAGE) $(JQ) $(STAGE)/.installed.md2conf
