<?
function rsperr($msg='', $st='400 Bad Request') {
	header('HTTP/1.1 '.$st);
	exit($msg);	
}
# Build path and url
if (!isset($_GET['name']) || !trim($_GET['name']))
	rsperr('missing name parameter');
$id = base_convert(md5($_GET['name'].' '.$_SERVER['REMOTE_ADDR']), 16, 36);
$name = $id . strrchr($_GET['name'], '.');
$path = dirname(realpath(__FILE__)).'/'.$name;
$url = (isset($_SERVER['HTTPS']) ? 'https://' : 'http://')
	. $_SERVER['SERVER_NAME'] . dirname($_SERVER['SCRIPT_NAME']) . '/' . $name;

# Save input to file
$dstf = @fopen($path, 'w');
if (!$dstf)
	rsperr('unable to write to '.dirname($path), '500 Internal Server Error');
$srcf = fopen('php://input', 'r');
$size = stream_copy_to_stream($srcf, $dstf);
fclose($dstf);

# Respond with the url
header('HTTP/1.1 201 Created');
header('Content-Type: text/plain; charset=utf-8');
header('Content-Length: '.strlen($url));
echo $url;
?>
