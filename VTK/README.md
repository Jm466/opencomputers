# VentanOS Tool Kit

VTK is a toolkit for creating VentanOS applicaction, it is inspired by java's swing library

## Explanation

The minimal unit in VTK is a component.
A component is just a table that knows how to draw itself to the screen.
Components are singlethreaded you cannot use threads or the library will likely break.

Components work in a hierarchy, at the root of the hierarchy is the `Component` class,
all other components must inherit from this table or a child(direct or indirect) of this table.

You can see all available components in the directory [/usr/lib/VTK/](https://github.com/Jm466/opencomputers/blob/master/VTK/src/lib/VTK).
You should also take a look at the file [/usr/lib/VTK/meta.lua](https://github.com/Jm466/opencomputers/blob/master/VTK/src/lib/VTK/meta.lua), in this file resides all the documentation for each component.
The meta file follows the [annotation syntax from the Lua language server](https://luals.github.io/wiki/annotations/#annotations-list).

Now follows a summary of the most important fields of the `Component` class, for the full documentation [see meta](https://github.com/Jm466/opencomputers/blob/master/VTK/src/lib/VTK/meta.lua).

- `width` and `height`: The width and height of the component, usefull to know when drawing the component.
- `set`, `fill` and `copy`: Like in [component GPU](https://ocdoc.cil.li/component:gpu). The coordinates are relative to the component, not the window or the screen,
  so (1,1) is topleft-most pixel that the component is responsible for drawing.
  The default values for fill are:

  `x` = 1, `y` = 1, `width` = component_width, `height` = component_height, `char` = " "

- `setBackground`, `setForeground`, `setPaletteColor`: Like in [component GPU](https://ocdoc.cil.li/component:gpu). The act for the whole window not just the component.
- `pref_width`, `pref_height`, `min_width`, `min_height`, `max_width` and `max_height`: The user of the component may change this values
  to control how much space the component gets assigned. As the component developer you do not have to look to these values
  when drawing the component, this are just for the parent component, the parent container will take this values into account
  when setting `width` and `height` of the component.

- `redraw_handler`: This function will get called when the component needs to get redrawn.
  You should use `set`, `fill` or `copy` for this purpuse, also check `width` and `height` to know the dimensions of the component.

- `touch_handler`, `drop_handler`, `drag_handler` and `scroll_handler`: Each of the these functions will be called
  when the corresponding event gets triggered.

## Creating your VTK app

Follow the steps for [creating your own app in VentanOS](https://github.com/Jm466/opencomputers/tree/master/VentanOS#Create-your-own-app) and continue here when creating the `init.lua`

Before using the toolkit you must always call `init`:

```lua
local frame = require("VTK").init()
```

`init` returns a frame, wich is a special type of Panel(a container for Components, [see meta](https://github.com/Jm466/opencomputers/blob/master/VTK/src/lib/VTK/meta.lua)).

You should also require all the components that you need, for instance, for using a button do:

```lua
local vtk_button = require("VTK/button")
```

Now you create instances of the Components that you want and add them to frame.

For a full application example see [vtk_test](https://github.com/Jm466/opencomputers/blob/master/VTK/src/ventanos_apps/vtk_test/init.lua).

## Creating a custom component

All components must inherit directly or indirectly from Component.

When creating your component see first if there is a more specific component that you can inherit from than Component.

Once you have decided who will be your father, you need to create a table by creating a new instance of the father and
after that you can override `init` in your new table so that it implements the constructor of your new Component,
finally you need to return a table with at least the `new` function(you need to at least define `new` so that this component can be inherited from,
you can also define other public constructors, [see](https://github.com/Jm466/opencomputers/blob/master/VTK/src/lib/VTK/Spacer.lua), that is between you and the component user).
`new` does not have any parameters and returns a new instance of your Component:

```lua
-- For this example let's take Component as our parent
local Component = require("VTK/core/Component")

local MyComponent = Component.new()

function MyComponent:init(my_component)
    my_component.var1 = 0
    my_component.var2 = 10
    my_component.var3 = {}
end

return {
    new = function()
        return MyComponent:new()
    end
}
```

Whenever `new` gets called, the Component class will make sure to execute the `init` at the class at the root and then the `init`
of the child classes(i.e. grandfather:init() -> father:init() -> MyComponent:init()) you may not define `init` if you have
nothing to initialize(it can be nil, it is checked).

For a full example see [Button](https://github.com/Jm466/opencomputers/blob/master/VTK/src/lib/VTK/Button.lua) or any file in [/usr/lib/VTK/](https://github.com/Jm466/opencomputers/blob/master/VTK/src/lib/VTK)
