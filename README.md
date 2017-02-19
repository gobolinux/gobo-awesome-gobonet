gobo-awesome-gobonet
====================

A GoboNet widget for Awesome WM.

Requirements
------------

* Awesome 3.5+
* [GoboNet](http://github.com/gobolinux/GoboNet)

Installing
----------

The easiest way to install it is via [LuaRocks](https://luarocks.org):


```
luarocks install gobo-awesome-gobonet
```

But you also have to edit your theme to add icons, see below.

Themeing
--------

It requires the following entries in your theme:

* `beautiful.wifi_3_icon`
* `beautiful.wifi_2_icon`
* `beautiful.wifi_1_icon`
* `beautiful.wifi_0_icon`
* `beautiful.wifi_down_icon`

You can use the ones in the `icons/` directory.

Using
-----

Require the module:


```
local gobonet = require("gobo.awesome.gobonet")
```

Create the widget with `gobonet.new()` and add to your layout.
In a typical `rc.lua` this will look like this:


```
right_layout:add(gobonet.new())
```

