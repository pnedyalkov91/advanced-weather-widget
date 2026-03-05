if [ -f "template.pot" ]; then
    newPotDate=`grep "POT-Creation-Date:" template.pot.new | sed 's/.\{3\}$//'`
    oldPotDate=`grep "POT-Creation-Date:" template.pot | sed 's/.\{3\}$//'`
    sed -i 's/'"${newPotDate}"'/'"${oldPotDate}"'/' "template.pot.new"
    changes=`diff "template.pot" "template.pot.new"`
    if [ ! -z "$changes" ]; then
        # There's been changes
        sed -i 's/'"${oldPotDate}"'/'"${newPotDate}"'/' "template.pot.new"
        mv "template.pot.new" "template.pot"

        addedKeys=`echo "$changes" | grep "> msgid" | cut -c 9- | sort`
        removedKeys=`echo "$changes" | grep "< msgid" | cut -c 9- | sort`
        echo ""
        echo "Added Keys:"
        echo "$addedKeys"
        echo ""
        echo "Removed Keys:"
        echo "$removedKeys"
        echo ""

    else
        # No changes
        rm "template.pot.new"
    fi
else
    # template.pot didn't already exist
    mv "template.pot.new" "template.pot"
fi

rm "${DIR}/infiles.list"
echo "[merge] Done extracting messages"
