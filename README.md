# Scrup

[<img src="http://farm3.static.flickr.com/2567/4121191747_3002198bb5_o.png" width="126" height="96" alt="Scrup icon" align="right" />](http://hunch.se/scrup/dist/scrup-1.3.2.zip) <img src="http://farm3.static.flickr.com/2522/4122092624_b2a9450bfe_o.png" width="350" height="382" alt="Scrup in the menu bar" /> [<img src="http://farm5.static.flickr.com/4058/4311662638_5ff27abfde_m.jpg" width="240" height="158" alt="Scrup 1.3" />](http://farm5.static.flickr.com/4058/4311662638_00be0d79d3_o.png)

Take a screenshot in OS X and have a URL to the picture in your pasteboard a second later.

*A free and open source version of the different commercial variants (GrabUp, Tiny Grab, etc).*

For Mac OS X 10.6 Snow Leopard.

## Download & install

- [Download Scrup](http://hunch.se/scrup/dist/scrup-1.3.2.zip)

- Move Scrup to your Applications folder and double-click the bastard.

- Scrup appears in the top right corner of your screen and looks like a twirly hand with and arrow. Click it and select "Preferences..."

- In the "Receiver URL" text field, enter the URL to something which receives files. For instance a copy of [`recv.php`](http://github.com/rsms/scrup/blob/master/recv.php) which you have uploaded to your server.

- Please note that the recv.php requires php5 to work, since it's using the PHP5-only stream_copy_to_stream() function to grab the image data stream.

- Take a screenshot and you should see the Scrup icon turning into a check mark, indicating success. (If you see a red badge something failed. Open Console.app and look what Scrup says.)

## Receivers & extensions

- **[django-scrup](http://github.com/idangazit/django-scrup/)** is a Django-based web receiver which stores screen captures on Amazon S3.

- **[Indexr](http://code.google.com/p/indexr/)** is a "small footprint image/file lister" written in PHP which provides a sort of browser/gallery. [Live demo here](http://firedev.com/indexr/)


## Details

- Lives in the menu bar (up there to your right, where the clock is).

- When a screenshot is taken, Scrup simply performs a `HTTP POST`, sending the image.

- After the screenshot has been sent, the server replies with the URL to the newly uploaded file.

- The URL is placed in the pasteboard, ready for you to  ⌘V somewhere.

There is an example PHP implementation called [`recv.php`](http://github.com/rsms/scrup/blob/master/recv.php) which you can use and/or modify to setup your receiver. Make sure to set your URL in the preferences.

## Building

You'll need libpngcrush to build Scrup. libpngcrush is an external submodule of Scrup which you'll need to update after you've checked out the scrup source:

	cd scrup-source
	git submodule update --init pngcrush

You only need to do this once. Now, build Scrup in Xcode.

## Authors

- Rasmus Andersson <http://hunch.se/>

## License

Open source licensed under MIT (see _LICENSE_ file for details).
