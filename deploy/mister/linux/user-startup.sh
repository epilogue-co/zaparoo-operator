#!/bin/bash

# mrext/zaparoo
[[ -e /media/fat/Scripts/zaparoo.sh ]] && /media/fat/Scripts/zaparoo.sh -service $1

#==== Epilogue Operator BEGIN ====
[ "$1" != "stop" ] && [ -x /media/fat/Scripts/.operator/zaparoo-operator ] && /media/fat/Scripts/.operator/zaparoo-operator bridge > /tmp/zaparoo-operator.log 2>&1 &
#==== Epilogue Operator END ====
