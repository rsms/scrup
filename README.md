# Scrup

Take a screenshot in OS X and have a URL to the picture in your pasteboard a second later.

In other words: a free and open source version of the different commercial variants (GrabUp, Tiny Grab, etc).

## Details

- Lives in the menu bar (up there to your right, where the clock is).

- When a screenshot is taken, Scrup simply performs a `HTTP POST`, sending the image.

- After the screenshot has been sent, the server replies with the URL to the newly uploaded file.

- The URL is placed in the pasteboard, ready for you to  ⌘V somewhere.

There is an example PHP implementation called `recv.php` which you can use and/or modify to setup your receiver. Make sure to set your URL in the preferences.

## Authors

- Rasmus Andersson <http://hunch.se/>

## License

Open source licensed under MIT (see _LICENSE_ file for details).
