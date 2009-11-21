/*!
 @brief    A Cocoa wrapper around LSSharedFileList for adding or removing Login Items.

 @details  SSYLoginItems.h/.c is an Obj-C wrapper on LSSharedFileList which provides some class methods to query, add and remove items from the user's "Login Items" in System Preferences.
 
 SSLoginItems.h/.c may be used in other projects.  Mac OS 10.5 and the CoreServices framework are required.
 
 QUICK START
 
 Run the demo project and follow the instructions in the console.  It will examine, add and remove items from your Login Items.  It will ask you to verify the results by examining your Login Items and then pressing return six times.
 
 BUGS
 
 When I run the program, I find two repeatable bugs:
 â€¢ In Test 1, Login Items that have the "Hidden" box checked are reported to have hidden=0.
 â€¢ In test 5, when the tool sets a Login Item with hidden=1, the "Hidden" box in Login Items does not get checked.
 
 I believe this is due to a bug in the LSShardFileList API which I have entered into Apple Bug Reporter.  Problem ID 5901742
 
 30-Apr-2008 01:48 PM Jerry Krinock: 
 
 * SUMMARY The 'hidden' attribute for Login Items in the LSSharedList API has a disconnect with the reality. In more detail, when reading a Login Item, the 'hidden' attribute is read as 0, even if it is in fact '1', unless the 'hidden' attribute has been set by the LSSharedList API. In that case, it doesn't really set, but when you read it back with the API, it says that it is set, even though in fact it is not.
 
 * STEPS TO REPRODUCE Build and run the attached project. Follow the prompts shown in the the console.
 
 * EXPECTED RESULTS In all tests, the values read and written using the LSSharedList API and shown in the log should agree with what is shown in the System Preferences application.
 
 * ACTUAL RESULTS In Test #1, items which have the "Hide" box checked in System Preferences read from the API hidden=0. In Test #5, although the API set Safari to "Hide" and the API read it back as hidden=1, if you look in System Preferences you see that the "Hide" box is not checked. 
*/




#import <Cocoa/Cocoa.h>

// Macros for making NSErrors

/*
 Quick macros to make a simple error without much thinking
 First argument is int, second is NSString*.
 */
#define SSYMakeError(_code,_localizedDetails) [NSError errorWithLocalizedDetails:_localizedDetails code:_code sender:nil selector:NULL]
#define SSYMakeHTTPError(_code) [NSError errorWithHTTPStatusCode:_code sender:nil selector:NULL]

/*
 Adds sender class and method name to the localized description,
 as described in errorWithLocalizedDetails:code:sender:selector below.
 This is good for errors which are not often expected; if you have a 
 "Copy to Clipboard" button or "Email this error to Support"
 on your alert users may copy and send it to your support email.
 This macro will only compile within an Objective-C method because
 it needs the local variables _cmd and self.
 First argument is int, second is NSString*.
 */ 
#define SSYMakeGeekyError(_code,_localizedDetails) [NSError errorWithLocalizedDetails:_localizedDetails code:_code sender:self selector:_cmd]
#define SSYMakeGeekyHTTPError(_code) [NSError errorWithHTTPStatusCode:_code sender:self selector:_cmd]

// Macros for initializing and assigning an NSError** named error_p

/*
 These are useful within functions that get an argument (NSError**)error_p
 Use SSYInitErrorP to assign it to *error_p to nil at beginning of function.
 (This is optional.  Apple doesn't do it in their methods that take NSError**,
 but I don't like the idea of leaving it unassigned.)
 Then, use the other three to assign to *error_p if/when an error occurs.
 Benefit: All of these macros check that error_p != NULL before assigning.
 */
#define SSYAssignErrorP(_error) if (error_p != NULL) {*error_p = _error ;}
#define SSYInitErrorP SSYAssignErrorP(nil) ;
#define SSYMakeAssignErrorP(_code,_localizedDetails) SSYAssignErrorP(SSYMakeError(_code,_localizedDetails))
#define SSYMakeAssignGeekyErrorP(_code,_localizedDetails) SSYAssignErrorP(SSYMakeGeekyError(_code,_localizedDetails))



@interface NSError (SSYAdditions) 

/*
 If sender != nil, will add the following line to localized description:
 "   Object Class: <name of sender's class>"
 If selector != nil, will add the following line to localized description:
 "   Method: <name of method>"
 */ 
+ (NSError*)errorWithLocalizedDetails:(NSString*)localizedDetails
								 code:(int)code
							   sender:(id)sender 
							 selector:(SEL)selector ;

/*
 If sender != nil, will add the following line to localized description:
 "   Object Class: <name of sender's class>"
 If selector != nil, will add the following line to localized description:
 "   Method: <name of method>"
 */ 
+ (NSError*)errorWithHTTPStatusCode:(int)code
							 sender:(id)sender 
						   selector:(SEL)selector ;


#pragma mark * Methods for adding userInfo keys to errors already created

/*!
 @brief    Adds or changes a string value for string key NSLocalizedDescriptionKey to userInfo 
 of a copy of the receiver and returns the copy
 @details  This may be used to change an error's localized description.
 @param    newText  The string value to be added for key NSLocalizedDescriptionKey
 @result   A new NSError object, identical to the receiver except for the localized description
 */
- (NSError*)errorByAddingLocalizedDescription:(NSString*)newText ;

/*!
 @brief    Adds a string value for string key NSLocalizedFailureReasonErrorKey to userInfo 
 a copy of the receiver and returns the copy
 @param    newText  The string value to be added for key NSLocalizedFailureReasonErrorKey
 @result   A new NSError object, identical to the receiver except for the additional key/value pair in userInfo
 */
- (NSError*)errorByAddingLocalizedFailureReason:(NSString*)newText ;

/*!
 @brief    Adds a string value for string key NSLocalizedRecoverySuggestionErrorKey to userInfo of a copy of
 the receiver and returns the copy
 @param    newText  The string value to be added for key NSLocalizedRecoverySuggestionErrorKey
 @result   A new NSError object, identical to the receiver except for the additional key/value pair in userInfo
 */
- (NSError*)errorByAddingLocalizedRecoverySuggestion:(NSString*)newText ;

/*!
 @brief    Adds an array value for string key NSLocalizedRecoveryOptionsErrorKey to userInfo of a copy of
 the receiver and returns the copy
 @param    options  The array of strings which will be added for key NSLocalizedRecoverySuggestionErrorKey
 @result   A new NSError object, identical to the receiver except for the additional key/value pair in userInfo
 */
- (NSError*)errorByAddingLocalizedRecoveryOptions:(NSArray*)recoveryOptions ;

/*!
 @brief    Adds an error for string key NSUnderlyingErrorKey to userInfo of a copy of 
 the receiver and returns the copy
 @param    underlyingError  The error value to be added for key NSUnderlyingErrorKey
 @result   A new NSError object, identical to the receiver except for the additional key/value pair in userInfo
 */
- (NSError*)errorByAddingUnderlyingError:(NSError*)underlyingError ;

/*!
 @brief    Adds object for key into the userInfo of a copy of the receiver and
 returns the copy
 @details  If the given key already has a value in the receiver's userInfo, then...
 If both existing and given values are NSStrings, the given is concatentated to the
 existing value with two newlines in between.  For other data types, the new value
 overwrites the existing value.
 @param    object  of the pair to be added
 @param    key  of the pair to be added
 @result   A new NSError object, identical to the receiver except for the additional key/value pair in userInfo
 */
- (NSError*)errorByAddingUserInfoObject:(id)object
								 forKey:(NSString*)key ;

/*!
 @brief    Adds keys and values explaining a given exception to the userInfo
 of a copy of the receiver and returns the copy.
 
 @param    exception  The exception whose info is to be added
 @result   A new NSError object, identical to the receiver except for the additional key/value pairs in userInfo
 */
- (NSError*)errorByAddingUnderlyingException:(NSException*)exception ;

@end




@interface SSYLoginItems : NSObject

enum SSYSharedFileListResult {
	SSYSharedFileListResultFailed = -1,
	SSYSharedFileListResultNoAction = 0,
	SSYSharedFileListResultAdded,
	SSYSharedFileListResultRemoved,
	SSYSharedFileListResultLaunched,
	SSYSharedFileListResultQuit,
	SSYSharedFileListResultSucceeded  // better to use one of the more specific values
} ;
/*!
    @enum       SSYSharedFileListResult
 @brief    Results for some of the methods in the SSYLoginItems class
    @constant   SSYSharedFileListResult
*/

/*!
 @brief    Tests whether or not the file URL url is a Login Item for the current user

 @details  Returns answer as [*isLoginItem_p boolValue].  If it is, also
 returns whether or not it is hidden as [*hidden_p boolValue]
 @param    url  The file url of the item in question
 @param    isLoginItem_p  On output, if input is not NULL, will point to 
 an [NSNumber numberWithBool:] expressing whether or not the item in question is a Login Item
 for the current user.
 @param    hidden_p  On output, if input is not NULL, will point to an [NSNumber numberWithBool:]
 expressing whether or not the item in question is "Hidden"
 in Login Items
 @param    error_p  On output, if input is not NULL, if error occurred, will point to an
 NSError* expressing the error which occurred.
 @result   YES if operation was successful with no error, NO otherwise.
 */
+ (BOOL)isURL:(NSURL*)url
	loginItem:(NSNumber**)isLoginItem_p
	   hidden:(NSNumber**)hidden_p
		error:(NSError**)error_p  ;

/*!
 @brief    Adds file URL url as a Login Item at the end of the list for the current user

 @details  Also, sets its 'hidden' parameter according to [hidden boolValue]
 @param    url  The file url of the item to be added.
 @param    hidden  The "Hidden" attribute of the new login item will be set to reflect this input.
 @param    error_p  On output, if input is not NULL, if error occurred, will point to an
 NSError* expressing the error which occurred.
 @result   YES if operation was successful with no error, NO otherwise.
 */
+ (BOOL)addLoginURL:(NSURL*)url
			 hidden:(NSNumber*)hidden
			  error:(NSError**)error_p ;

/*!
 @brief    Removes file URL url as a Login Item for the current user
 @param    url  The file url of the item to be removed.
 @param    error_p  On output, if input is not NULL, if error occurred, will point to an
 NSError* expressing the error which occurred.
 @result   YES if operation was successful with no error, NO otherwise.
 */
+ (BOOL)removeLoginURL:(NSURL*)url
				 error:(NSError**)error_p ;

/*!
 @brief    Adds <i>or</i> removes an item to/from Login Items of current user

 @details  If path is not a Login Item for the current user and shouldBeLoginItem is
 YES, makes it a Login Item for the current user and also sets it hidden or
 not according to setHidden.
 If path is a Login Item for the current user and shouldBeLoginItem is NO,
 removes path from current user's Login items.
 If neither of the above, does nothing.
 @param    The  absolute path to the item which will be added or removed from Login Items.
 @param    shouldBeLoginItem  Whether the item should be a Login Item or not.
 @param    setHidden  If a new login item is set, whether or not it is set as Hidden.
 @param    error_p  On output, if input is not NULL, if error occurred, will point to an
 NSError* expressing the error which occurred.
 @result   If operation fails for some reason, returns SSYSharedFileListResultFailed
 If item at path was not found and added, returns SSYSharedFileListResultAdded.
 If item at path was found and removed, returns SSYSharedFileListResultRemoved.
 If none of the above occurred, returns SSYSharedFileListResultNoAction.
 */
+ (enum SSYSharedFileListResult)synchronizeLoginItemPath:(NSString*)path
									   shouldBeLoginItem:(BOOL)shouldBeLoginItem
											   setHidden:(BOOL)setHidden 
												   error:(NSError**)error_p ;

/*!
 @brief    Removes all Login Items for the current user which have a given name as last
 component of their path name, except those in a given path.

 @details  This method is useful to clear out login items referring to old
 versions, after the installation of a Login Item has been updated.  In this case,
 pass path as the latest version of the app to be launched.
 @param    name  Filename (last component of path name) used to qualify Login Items
 for removal.  The .extension part of this argument, if any, is ignored.
 @param    path  Login Items in this path will not be removed.
 @param    error_p  On output, if input is not NULL, if error occurred, will point to an
 NSError* expressing the error which occurred.
 @result   If operation fails for some reason, returns SSYSharedFileListResultFailed
 If one or more Login Items were removed, returns SSYSharedFileListResultRemoved.
 If zero Login Items were removed, returns SSYSharedFileListResultNoAction.
 */
+ (enum SSYSharedFileListResult)removeAllLoginItemsWithName:(NSString*)name
										   thatAreNotInPath:(NSString*)path
													  error:(NSError**)error_p ;

@end
