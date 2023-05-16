# NAME

Mail::SpamAssassin::Plugin::AttachmentDetail - SpamAssassin plugin to check attachment details

# DESCRIPTION

This plugin creates a new rule test type, called "attachment".  These
rules apply to all attachments found in the message. Any MIME part
that has a filename is considered an "attachment" regardless of the content
disposition.

# SYNOPSIS

    loadplugin    Mail::SpamAssassin::Plugin::AttachmentDetail

    attachment    INVALID_HTML_TYPE       name =~ /\.s?html?/i type != text/html
    attachment    GEEKSQUAD_IMAGE_SPAM    name =~ /^geek/i type =~ /^image\//
    attachment    TRAILING_DOT            name =~ /\.$/
    attachment    DOUBLE_EXTENSION        name =~ /\.[^.\/\s]{2,4}\.[^.\/\s]{2,4}$/i
    ...

    body          __ATTACH_NONE             eval:check_attachment_count(0,0)
    body          __ATTACH_SINGLE           eval:check_attachment_count(1,1)
    body          __ATTACH_MULTI            eval:check_attachment_count(2,9999)

This plugin also creates the following eval rule:

    body RULENAME  eval:check_attachment_count(<min>, <max>)
       min: minimum number of attachments
       max: maximum number of attachments

       Returns true if the number of attachments is between min and max (inclusive).

# FAQ

Q: Can't I just use a `mimeheader` rule to check attachment details? For example, I already have this rule to
look for HTML attachments with the wrong MIME type:

    mimeheader  OBFU_HTML_ATTACH   Content-Type =~ m,\bapplication/octet-stream\b.+\.s?html?\b,i

A: There's a few problems with this approach. First, the filename is not always included in the Content-Type header.
It can be included in the Content-Disposition header instead. For example:

    Content-Type: application/octet-stream;
    Content-Disposition: attachment; filename="document.html"

Second, the filename can be encoded and split across multiple lines using Parameter Value Continuation. For example:

    Content-Type: application/octet-stream;
        name*0*=UTF-8''%64%6F%63%75%6D%65%6E
        name*1*=%74%2E%68%74%6D%6C

As of SA version 4.0.0, the `mimeheader` rule does not properly decode Parameter Value Continuation. This plugin does.
For more information on Parameter Value Continuation, see RFC 2231. [https://datatracker.ietf.org/doc/html/rfc2231](https://datatracker.ietf.org/doc/html/rfc2231)

Third, it's easy to make mistakes when writing regular expressions. For example, the above rule will match
any filename that contains the string ".html" such as "document.html.zip" which may or may not be
what you want. This plugin simplifies the process of writing rules for attachments, leading to fewer mistakes.

# RULE DEFINITIONS

The format for defining a rule is as follows:

    attachment SYMBOLIC_TEST_NAME key1 =~ /value1/i  key2 == value2 ...

Supported keys are:

`name` is the suggested filename as specified in the Content-Type header

`type` is the attachment MIME type (e.g. image/png, application/pdf, etc.)

`disposition` is the content disposition (e.g. attachment or inline)

`encoding` is the content transfer encoding (e.g. 7bit, base64, quoted-printable, etc.)

`charset` is the character set (e.g. us-ascii, UTF-8, Windows-1251, ISO-8859-1, etc.)

Supported operators are:

`==` equal to

`!=` not equal to

`=~` matches regular expression

`!~` does not match regular expression

Regular expressions should be delimited by slashes and can optionally include modifiers after the terminating slash.
Text values may be enclosed in single or double quotes. Quotes may be omitted as long as the text does not
contain any spaces.

If more than one condition is specified on a single rule, then ALL conditions must be true for the test to hit
(i.e. logical AND).

# TAGS

This plugin adds the following tags:

`ATTACHMENT_COUNT` is the number of attachments found in the message

`ATTACHMENT_TYPES` is a comma-separated list of all the MIME types found in the message

`ATTACHMENT_EXTS` is a comma-separated list of all the file extensions found in the message

You can add custom headers to the message by adding the following to your local.cf:

    add_header all Attachment-Count _ATTACHMENT_COUNT_
    add_header all Attachment-Types _ATTACHMENT_TYPES_
    add_header all Attachment-Exts _ATTACHMENT_EXTS_

This will add headers to the message like this:

    X-Spam-Attachment-Count: 2
    X-Spam-Attachment-Types: image/png, application/pdf
    X-Spam-Attachment-Exts: png, pdf

# ACKNOWLEDGEMENTS

This plugin was modeled after the URIDetail plugin

# REQUIREMENTS

Email::MIME::ContentType 1.022 or later

# AUTHORS

Kent Oyer <kent@mxguardian.net>

# COPYRIGHT AND LICENSE

Copyright (C) 2023 MXGuardian LLC

This is free software; you can redistribute it and/or modify it under
the terms of the Apache License 2.0. See the LICENSE file included
with this distribution for more information.

This plugin is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
