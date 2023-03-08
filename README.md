# NAME

AttachmentDetail - SpamAssassin plugin to check attachment details

# DESCRIPTION

This plugin creates a new rule test type, called "attachment".  These
rules apply to all attachments found in the message. Any MIME part
that has a filename is considered an "attachment" regardless of the content
disposition.

This provides a simpler way to write rules based on filenames and MIME types without having to
parse MIME headers yourself.

# SYNOPSIS

    loadplugin    Mail::SpamAssassin::Plugin::AttachmentDetail

    attachment    INVALID_HTML_TYPE       name =~ /\.s?html?/i type != "text/html"
    attachment    GEEKSQUAD_IMAGE_SPAM    name =~ /^geek/i type =~ /^image\//
    attachment    TRAILING_DOT            name =~ /\.$/
    attachment    DOUBLE_EXTENSION        name =~ /\.[^.\/\s]{2,4}\.[^.\/\s]{2,4}$/i
    ...

# RULE DEFINITIONS AND PRIVILEGED SETTINGS

The format for defining a rule is as follows:

    attachment SYMBOLIC_TEST_NAME key1 =~ /value1/i  key2 == value2 ...

Supported keys are:

`name` is the suggested filename as specified in the Content-Disposition header

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

# ACKNOWLEDGEMENTS

This plugin was modeled after the URIDetail plugin
