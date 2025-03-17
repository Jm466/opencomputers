# VentanOS

VentanOS is a window manager for openos inspired by Microsoft's Windows xp

[![](img.png)](https://youtu.be/0-JKaqwn-nA?si=Tumqwfv4NvE_KHTW)
(click image for demo)

## Installation

### Install with [OPPM](https://ocdoc.cil.li/tutorial:program:oppm)

Register the repository and install the program

```bash
oppm register Jm466/opencomputers
oppm install ventanos
```

## How to use

Once installed you can launch VentanOS with the `ventanos` command:

```
$ ventanos
```

You can create new windows by pressing the bottom left button, doing so will create a new window with the Programs launcher app opened.
The Programs launcher will show all available apps, to start any app you just click the app icon and the Programs launcher will
run the app on the currently open window.

### Window management

You can resize any window by clicking at any of the four @ at the four edges.

You can maximize the window by pressing the ■ icon at the top left corner.

You can NOT minimize the window at the moment.

## Explanation

When a window gets printed to the screen it naturally overrides the pixels of region of the screen that
the window is drawn to.

VentanOS is created with the idea that each window is responsable to storing this information before the window
being displayed and restoring that pixel region to the screen when the window closes or changes dimensions;
this is achived by asociating each window with a [Video Ram Buffer](https://ocdoc.cil.li/component:gpu#video_ram_buffers)
wich is the size of the window, so when a window gets created it will follow the following process:

1. A new window gets created at desktop position w_x,w_y with dimensions w_w,w_h
2. A new Video Ram Buffer gets allocated with size w_w,w_h
3. Transfer the pixels to the buffer: [bitblt](https://ocdoc.cil.li/component:gpu#video_ram_buffers)(buffer, 1, 1, w_w, w_h, 0, w_x, w_y)
4. The new window can now be drawn at w_x,w_y

When the window gets closed the buffer is restored to the screen and freed.

For moving and resize the window it is just a matter of cleverly move pixels between buffers around.
Check the [change_geometry function in window_manager.lua](src/lib/ventanos/window_manager.lua) this is the function
that does all the work of resizing and moving windows around.

All of this process is implemented at the VentanOS level, this process is completely invisible to any application

## Create your own app

First you need to create a directory for your app in one of the following directories:

`/usr/ventanos_apps`, `/usr/lib/ventanos_apps`, `/home/ventanos_apps`, `/home/lib/ventanos_apps`

For instance: `/home/ventanos_app/my_app/`

In that directory you need to create the following files:

- `name`: Contains the name of the application
- `logo.ppm`: (Optional, if missing will use the default logo) The logo for the application, must be 14 pixels wide by 7 tall and in the [PPM binary(raw) format](https://en.wikipedia.org/wiki/Netpbm#Description)(you can use a program like [GIMP](https://www.gimp.org/) to create and export to that format)
- `init.lua` This is where the entry point to the application will be searched for.
  You have two options: Use the [VentanOS ToolKit](https://github.com/Jm466/opencomputers/tree/master/VTK) or create it using the VentanOS api, you cannot mix the two.
  VTK is recommended for creating more complex UIs whereas the VentanOS API can be used to write very simple UIs with very simple code.

### VentanOS API

Coordinates start at the first drawable pixel and end at the last:

```
@MyApp──────T_■X@
│F         ^    │
│          |    │
│<--width--┼--->│
│          |    │
│      height   │
│          |    │
@          v   L@
```

`F` is at the first drawable pixel(1, 1)

`L` is at the last drawable pixel(viewport_width, viewport_height)

#### Signals interface

In the `init.lua` file you can define the following global functions:

```lua
function Redraw()
    -- Redraw code
end

function Touch(x, y, button)
    -- Touch event handle code
end

function Drop(x, y, button)
    -- Drop event handle code
end

function Drag(x, y, button)
    -- Drag event handle code
end

function Scroll(x, y, direcction)
    -- Drag event handle code
end

function Main()
    -- Init code for your app
end
```

Of these functions, the only one that is mandatory to implement is `Redraw`.
`Redraw` will be called every time the window needs to be redrawn.
When `Redraw` is called, you are expected to completely redraw the entire window.
The `Main` function gets called exactly once, after the program has finished loading.
You can put the initialization code inside this function.
The only difference between putting code inside and outside of `Main` is that, if the application crashes,
if the crashing code is in `Main` the backtrace will be more detailled, also, all the global functions of the signal handlers should be
accesible, no matter if `Main` is defined at the top of the file.
The rest of the functions are called when the corresponding [event](https://ocdoc.cil.li/component:signals#screen) is triggered.

#### API interface

What follows are the functions available for sending orders to the window manager.
Most of these are reimplementations of the GPU component but in the context of the window instead of the whole screen.
As such, all coordinates and dimensions are relative to the window.
Position 1,1 is the top-left pixel of the window, not the screen, and the width and height of the viewport are the width and height of the window, not the screen.

`setTitle(new_title: string)`

Sets the title of the window.

`kill()`

Kills the window, like if the user clicked the X button.

`print(...): boolean, string`

Good ol'd print. It will print inside the window.

`setCursor(x: number, y: number):boolean`

Like in the [term api](https://ocdoc.cil.li/api:term).

`setBackground(color: number, isPaletteIndex: boolean?)`

Like in the [gpu component](https://ocdoc.cil.li/component:gpu).

`setForeground(color: number, isPaletteIndex: boolean?)`

Like in the [gpu component](https://ocdoc.cil.li/component:gpu).

`setPaletteColor(index: number, value: number)`

Like in the [gpu component](https://ocdoc.cil.li/component:gpu).

`set(x: number, y: number, value: string, vertical: boolean?): boolean, string`

Like in the [gpu component](https://ocdoc.cil.li/component:gpu).
Additionaly, if the opperation could not be performed, returns false and the reason of the failure.

`copy(x: number, y: number, width: number, height:number, tx:number, ty:number): boolean, string`

Like in the [gpu component](https://ocdoc.cil.li/component:gpu).
Additionaly, if the opperation could not be performed, returns false and the reason of the failure.

`fill(x:number?, y:number?, width:number?, height:number?, char:string?): boolean, string`

Like in the [term api](https://ocdoc.cil.li/api:term).
Additionaly, if the opperation could not be performed, returns false and the reason of the failure.
The default values for each parameter are:

`x` = 1, `y` = 1, `width` = viewport_width, `height` = viewport_height, `char` = " "

`getViewport():integer, integer`

Like in the [gpu component](https://ocdoc.cil.li/component:gpu).
For a full application example see [test](https://github.com/Jm466/opencomputers/tree/master/VentanOS/src/ventanos_apps/test).

### Multi-window applications

Personally, I believe that multi-window applications are a mistake, but they are definitely technologically possible in VentanOS!

First you need to require the ventanos library:

```lua
local ventanos = require("ventanos")
```

Now you can call the `new` function:

`new(title: string, redraw_handler: fun, touch_handler: fun?, drop_handler: fun?, drag_handler: fun?, scroll_handler: fun?)`

Creates a new window with title `title`, you must also include a redraw handler for that window.
So, like above, `redraw_handler` is a function that will be called when the window needs to get redrawn.
And the rest of function are handling their respective events.
As you can see there is no `Main` function for the new window, as you are creating a new window, not a new application.

For accessing the API Interface functions, each of them is callable as a method through the handle returned by `new`

```lua
-- This is a complete example
local ventanos = require("ventanos")

function Redraw()
    fill()
end

function Main()
    setTitle("creating the child window...")
    os.sleep(3)

    local child_window -- We declare the variable first so we can use it for the child's Redraw
    child_window = ventanos.new("child window", function() child_window:fill() end)

    setTitle("child window created")

    os.sleep(5)
    child_window:setTitle("Kaboom!")
    os.sleep(1)
    child_window:kill()
end
```
