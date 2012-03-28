//
//  SPPlaybackManager.m
//  Guess The Intro
//
//  Created by Daniel Kennett on 06/05/2011.
/*
 Copyright (c) 2011, Spotify AB
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * Neither the name of Spotify AB nor the names of its contributors may 
 be used to endorse or promote products derived from this software 
 without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL SPOTIFY AB BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT 
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, 
 OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SPPlaybackManager.h"
#import "SPCoreAudioController.h"
#import "SPTrack.h"
#import "SPSession.h"
#import "SPErrorExtensions.h"

@interface SPPlaybackManager ()

@property (nonatomic, readwrite, retain) SPCoreAudioController *audioController;
@property (nonatomic, readwrite, retain) SPTrack *currentTrack;
@property (nonatomic, readwrite, retain) SPSession *playbackSession;

@property (readwrite) NSTimeInterval trackPosition;

-(void)informDelegateOfAudioPlaybackStarting;

@end

static NSString * const kSPPlaybackManagerKVOContext = @"kSPPlaybackManagerKVOContext"; 

@implementation SPPlaybackManager

-(id)initWithPlaybackSession:(SPSession *)aSession {
    
    if ((self = [super init])) {
        
        self.playbackSession = aSession;
		self.playbackSession.playbackDelegate = (id)self;
		self.audioController = [[[SPCoreAudioController alloc] init] autorelease];
		self.audioController.delegate = self;
		self.playbackSession.audioDeliveryDelegate = self.audioController;
		
		[self addObserver:self
			   forKeyPath:@"playbackSession.playing"
				  options:0
				  context:kSPPlaybackManagerKVOContext];
	}
    return self;
}

-(void)dealloc {
	
	[self removeObserver:self forKeyPath:@"playbackSession.playing"];
	
	self.playbackSession.playbackDelegate = nil;
	self.playbackSession = nil;
	self.currentTrack = nil;
	
	self.audioController = nil;
	
    [super dealloc];
}

@synthesize audioController;
@synthesize playbackSession;
@synthesize trackPosition;
@synthesize delegate;

+(NSSet *)keyPathsForValuesAffectingVolume {
	return [NSSet setWithObject:@"audioController.volume"];
}

-(double)volume {
	return self.audioController.volume;
}

-(void)setVolume:(double)volume {
	self.audioController.volume = volume;
}

@synthesize currentTrack;

-(BOOL)playTrack:(SPTrack *)trackToPlay error:(NSError **)error {
	
	self.playbackSession.playing = NO;
	[self.playbackSession unloadPlayback];
	[self.audioController clearAudioBuffers];
	
	if (trackToPlay.availability != SP_TRACK_AVAILABILITY_AVAILABLE) {
		if (error != NULL) *error = [NSError spotifyErrorWithCode:SP_ERROR_TRACK_NOT_PLAYABLE];
		self.currentTrack = nil;
		return NO;
	}
		
	self.currentTrack = trackToPlay;
	self.trackPosition = 0.0;
	BOOL result = [self.playbackSession playTrack:self.currentTrack error:error];
	if (result)
		self.playbackSession.playing = YES;
	else
		self.currentTrack = nil;
	
	return result;
}

-(void)seekToTrackPosition:(NSTimeInterval)newPosition {
	if (newPosition <= self.currentTrack.duration) {
		[self.playbackSession seekPlaybackToOffset:newPosition];
		self.trackPosition = newPosition;
	}	
}

+(NSSet *)keyPathsForValuesAffectingIsPlaying {
	return [NSSet setWithObject:@"playbackSession.playing"];
}

-(BOOL)isPlaying {
	return self.playbackSession.isPlaying;
}

-(void)setIsPlaying:(BOOL)isPlaying {
	self.playbackSession.playing = isPlaying;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    
	if ([keyPath isEqualToString:@"playbackSession.playing"] && context == kSPPlaybackManagerKVOContext) {
        self.audioController.audioOutputEnabled = self.playbackSession.isPlaying;
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

#pragma mark -
#pragma mark Audio Controller Delegate

-(void)coreAudioController:(SPCoreAudioController *)controller didOutputAudioOfDuration:(NSTimeInterval)audioDuration {
	
	if (self.trackPosition == 0.0)
		dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate playbackManagerWillStartPlayingAudio:self]; });
	
	self.trackPosition += audioDuration;
}

#pragma mark -
#pragma mark Playback Callbacks

-(void)sessionDidLosePlayToken:(SPSession *)aSession {

	// This delegate is called when playback stops because the Spotify account is being used for playback elsewhere.
	// In practice, playback is only paused and you can call [SPSession -setIsPlaying:YES] to start playback again and 
	// pause the other client.

}

-(void)sessionDidEndPlayback:(SPSession *)aSession {
	
	// This delegate is called when playback stops naturally, at the end of a track.
	
	// Not routing this through to the main thread causes odd locks and crashes.
	[self performSelectorOnMainThread:@selector(sessionDidEndPlaybackOnMainThread:)
						   withObject:aSession
						waitUntilDone:NO];
}

-(void)sessionDidEndPlaybackOnMainThread:(SPSession *)aSession {
	self.currentTrack = nil;	
}


-(void)informDelegateOfAudioPlaybackStarting {
	if (![NSThread isMainThread]) {
		[self performSelectorOnMainThread:_cmd withObject:nil waitUntilDone:NO];
		return;
	}
	[self.delegate playbackManagerWillStartPlayingAudio:self];
}

@end
