# CFG::Config

A Ruby library for working with the CFG configuration format.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'cfg-config'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install cfg-config

## Usage

The CFG configuration format is a text format for configuration files which is similar to, and a superset of, the JSON format. It dates from before its first announcement in [2008](https://wiki.python.org/moin/HierConfig) and has the following aims:

* Allow a hierarchical configuration scheme with support for key-value mappings and lists.
* Support cross-references between one part of the configuration and another.
* Provide a string interpolation facility to easily build up configuration values from other configuration values.
* Provide the ability to compose configurations (using include and merge facilities).
* Provide the ability to access real application objects safely, where supported by the platform.
* Be completely declarative.

It overcomes a number of drawbacks of JSON when used as a configuration format:

* JSON is more verbose than necessary.
* JSON doesn’t allow comments.
* JSON doesn’t provide first-class support for dates and multi-line strings.
* JSON doesn’t allow trailing commas in lists and mappings.
* JSON doesn’t provide easy cross-referencing, interpolation, or composition.

A simple example
================

With the following configuration file, `test0.cfg`:
```text
a: 'Hello, '
b: 'world!'
c: {
  d: 'e'
}
'f.g': 'h'
christmas_morning: `2019-12-25 08:39:49`
home: `$HOME`
foo: `$FOO|bar`
```

You can load and query the above configuration using, for example, [irb](https://ruby-doc.org/stdlib-2.4.0/libdoc/irb/rdoc/IRB.html):

Loading a configuration
-----------------------

The configuration above can be loaded as shown below. In the REPL shell:
```text
2.7.1 :001 > require 'CFG/config'
 => true
2.7.1 :002 > include CFG
 => Object
2.7.1 :003 > cfg = CFG::Config::new("test0.cfg")
```

The successful `new()` call returns a `Config` instance which can be used to query the configuration.

Access elements with keys
-------------------------
Accessing elements of the configuration with a simple key is not much harder than using a `Hash`:
```text
2.7.1 :004 > cfg['a']
 => "Hello, "
2.7.1 :005 > cfg['b']
 => "world!"
```

Access elements with paths
--------------------------
As well as simple keys, elements can also be accessed using path strings:
```text
2.7.1 :006 > cfg['c.d']
 => "e"
```
Here, the desired value is obtained in a single step, by (under the hood) walking the path `c.d` – first getting the mapping at key `c`, and then the value at `d` in the resulting mapping.

Note that you can have simple keys which look like paths:
```text
2.7.1 :007 > cfg['f.g']
 => "h"
```
If a key is given that exists in the configuration, it is used as such, and if it is not present in the configuration, an attempt is made to interpret it as a path. Thus, `f.g` is present and accessed via key, whereas `c.d` is not an existing key, so is interpreted as a path.

Access to date/time objects
---------------------------
You can also get native Ruby date/time objects from a configuration, by using an ISO date/time pattern in a backtick-string:
```text
2.7.1 :008 > cfg['christmas_morning']
 => #<DateTime: 2019-12-25T08:39:49+00:00 ((2458843j,31189s,0n),+0s,2299161j)>
```
Access to other Ruby objects
----------------------------
Access to other Ruby objects is also possible using the backtick-string syntax, provided that they are one of:
* Environment variables
* Public fields of public classes
* Public static methods without parameters of public classes
```text
2.7.1 :009 > require 'date'
 => false
2.7.1 :010 > DateTime::now - cfg['now']
 => (-148657/86400000000000)
 ```

Access to environment variables
-------------------------------
To access an environment variable, use a backtick-string of the form `$VARNAME`:
```text
2.7.1 :011 > cfg['home'] == ENV['HOME']
 => true
```
You can specify a default value to be used if an environment variable isn’t present using the `$VARNAME|default-value` form. Whatever string follows the pipe character (including the empty string) is returned if the VARNAME is not a variable in the environment.
```text
2.7.1 :012 > cfg['foo']
 => "bar"
```

For more information, see [the CFG documentation](https://docs.red-dove.com/cfg/index.html).
