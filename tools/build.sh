#!/usr/bin/env bash
prove -l t
echo "Updating README.md"
pod2markdown lib/Mail/SpamAssassin/Plugin/AttachmentDetail.pm >README.md
