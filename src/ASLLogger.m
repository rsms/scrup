/*
 * Copyright (c) 2009 Rasmus Andersson
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
#import "ASLLogger.h"

static char *identity = NULL;
static char *facility = NULL;


@implementation ASLConnection

- (id)initWithOptions:(uint32_t)options {
  if ((self = [self init])) {
    filter = ASL_FILTER_MASK_UPTO(ASL_LEVEL_NOTICE);
    aslc = asl_open(identity, facility, options);
  }
  return self;
}

- (void)setFilter:(uint32_t)u {
  filter = u;
  asl_set_filter(aslc, u);
}

- (uint32_t)filter {
  return filter;
}

- (void)setLevel:(uint32_t)level {
  self.filter = ASL_FILTER_MASK_UPTO(level);
}

- (uint32_t)level {
  if ((filter & ASL_FILTER_MASK_DEBUG) == ASL_FILTER_MASK_DEBUG)
    return ASL_LEVEL_DEBUG;
  if ((filter & ASL_FILTER_MASK_INFO) == ASL_FILTER_MASK_INFO)
    return ASL_LEVEL_INFO;
  if ((filter & ASL_FILTER_MASK_NOTICE) == ASL_FILTER_MASK_NOTICE)
    return ASL_LEVEL_NOTICE;
  if ((filter & ASL_FILTER_MASK_WARNING) == ASL_FILTER_MASK_WARNING)
    return ASL_LEVEL_WARNING;
  if ((filter & ASL_FILTER_MASK_ERR) == ASL_FILTER_MASK_ERR)
    return ASL_LEVEL_ERR;
  if ((filter & ASL_FILTER_MASK_CRIT) == ASL_FILTER_MASK_CRIT)
    return ASL_LEVEL_CRIT;
  if ((filter & ASL_FILTER_MASK_ALERT) == ASL_FILTER_MASK_ALERT)
    return ASL_LEVEL_ALERT;
  if ((filter & ASL_FILTER_MASK_EMERG) == ASL_FILTER_MASK_EMERG)
    return ASL_LEVEL_EMERG;
  return -1;
}

- (void)finalize {
  asl_close(aslc);
	[super finalize];
}

- (void)dealloc {
  asl_close(aslc);
  [super dealloc];
}

@end


@implementation ASLLogger


+ (void)setIdentity:(NSString *)s {
  if (identity)
    free(identity);
  const char *src = [s UTF8String];
  identity = (char *)malloc(strlen(src)+1);
  strcpy(identity, src);
}


+ (void)setFacility:(NSString *)s {
  if (facility)
    free(facility);
  const char *src = [s UTF8String];
  facility = (char *)malloc(strlen(src)+1);
  strcpy(facility, src);
}


+ (ASLLogger *)loggerForModule:(NSString *)ident {
  ASLLogger *logger;
  NSMutableDictionary *thd;
  NSString *thdKey;
  thdKey = [@"ASLLogger_" stringByAppendingString:ident];
  thd = [[NSThread currentThread] threadDictionary];
  if ( !(logger = [thd objectForKey:thdKey]) ) {
    logger = [[ASLLogger alloc] initWithModule:ident];
    [thd setObject:logger forKey:thdKey];
  }
  return logger;
}


+ (ASLLogger *)defaultLogger {
  return [ASLLogger loggerForModule:@""];
}


+ (void)releaseLoggerForModule:(NSString *)ident {
  NSString *thdKey;
  NSMutableDictionary *thd;
  thdKey = [@"ASLLogger_" stringByAppendingString:ident];
  thd = [[NSThread currentThread] threadDictionary];
  [thd removeObjectForKey:thdKey];
}


+ (void)releaseLoggers {
  NSMutableDictionary *thd;
  NSMutableArray *rmkeys;
  NSRange range;
  thd = [[NSThread currentThread] threadDictionary];
  rmkeys = [[NSMutableArray alloc] init];
  range = NSMakeRange(0, 10);
  for (NSString *key in thd) {
    if ([@"ASLLogger_" compare:key options:0 range:range] == 0) {
      [rmkeys addObject:key];
    }
  }
  [thd removeObjectsForKeys:rmkeys];
}


- (id)initWithModule:(NSString *)mod {
  if ((self = [self init])) {
    if ([mod length])
      module = mod;
  }
  return self;
}


- (id)init {
  NSMutableDictionary *thd;
  NSString *thdKey;
  if ((self = [super init])) {
    module = nil;
    thdKey = [NSString stringWithFormat:@"ASLConnection_%s_%s", 
      identity ? identity : "",
      facility ? facility : ""];
    thd = [[NSThread currentThread] threadDictionary];
    if (!(connection = [thd objectForKey:thdKey])) {
      // new connection
      connection = [(ASLConnection *)[ASLConnection alloc] initWithOptions:0];
      [thd setObject:connection forKey:thdKey];
    }
  }
  return self;
}


- (ASLConnection *)connection {
  return connection;
}


- (BOOL)addFileDescriptor:(int)fd {
  return asl_add_log_file(connection->aslc, fd) == 0;
}

- (BOOL)addFileHandle:(NSFileHandle *)fh {
  return [self addFileDescriptor:[fh fileDescriptor]];
}

- (BOOL)removeFileDescriptor:(int)fd {
  return asl_remove_log_file(connection->aslc, fd) == 0;
}

- (BOOL)removeFileHandle:(NSFileHandle *)fh {
  return [self removeFileDescriptor:[fh fileDescriptor]];
}


- (void)emit:(int)level format:(NSString *)format arguments:(va_list)args {
  NSString *s = [[NSString alloc] initWithFormat:format arguments:args];
  const char *pch = [s UTF8String];
  if (module)
    asl_log(connection->aslc, NULL, level, "[%s] %s", [module UTF8String], pch);
  else
    asl_log(connection->aslc, NULL, level, "%s", pch);
}


#define L(level, LEVEL)\
- (void)level:(NSString *)format, ... {\
  va_list args;\
  va_start(args, format);\
  [self emit:ASL_LEVEL_ ##LEVEL format:format arguments:args];\
  va_end(args);\
}
L(emerg,    EMERG)
L(alert,    ALERT)
L(crit,     CRIT)
L(error,    ERR)
L(err,      ERR)
L(warn,     WARNING)
L(warning,  WARNING)
L(notice,   NOTICE)
L(info,     INFO)
L(debug,    DEBUG)
#undef L


- (void)finalize {
  module = nil;
  connection = nil;
	[super finalize];
}


@end
