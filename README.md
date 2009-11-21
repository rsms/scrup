# Scrup

[<img src="http://farm3.static.flickr.com/2567/4121191747_3002198bb5_o.png" width="126" height="96" alt="Scrup icon" align="right" />](http://hunch.se/scrup/dist/scrup-1.0.zip)

Take a screenshot in OS X and have a URL to the picture in your pasteboard a second later.

*A free and open source version of the different commercial variants (GrabUp, Tiny Grab, etc).*

For Mac OS X 10.6 Snow Leopard.

## Download & install

- [Download Scrup 1.0](http://hunch.se/scrup/dist/scrup-1.0.zip)

- Move Scrup to your Applications folder and double-click the bastard.

- Scrup appears in the top right corner of your screen and looks like a twirly hand with and arrow. Click it and select "Preferences..."

- In the "Receiver URL" text field, enter the URL to something which receives files. For instance a copy of [`recv.php`](http://github.com/rsms/scrup/blob/master/recv.php) which you have uploaded to your server.

- Take a screenshot and you should see the Scrup icon turning into a check mark, indicating success. (If you see a red badge something failed. Open Console.app and look what Scrup says.)


## Details

- Lives in the menu bar (up there to your right, where the clock is).

- When a screenshot is taken, Scrup simply performs a `HTTP POST`, sending the image.

- After the screenshot has been sent, the server replies with the URL to the newly uploaded file.

- The URL is placed in the pasteboard, ready for you to  ⌘V somewhere.

There is an example PHP implementation called [`recv.php`](http://github.com/rsms/scrup/blob/master/recv.php) which you can use and/or modify to setup your receiver. Make sure to set your URL in the preferences.

## Authors

- Rasmus Andersson <http://hunch.se/>

## License

Open source licensed under MIT (see _LICENSE_ file for details).
