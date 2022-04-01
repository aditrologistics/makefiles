require=$(if ${$(strip $(1))}, \
	@echo $(1) is defined to $($(strip $(1))), \
	$(error $(1) must be defined$(if $(2), in target '$(strip $(2))')))

ifeq ($(OS),Windows_NT)
HOMEDIR=$(subst C:,/c,$(subst \,/,$(USERPROFILE)))
else
HOMEDIR=~
endif

MKTARGETDIR=mkdir -p $(dir $@)