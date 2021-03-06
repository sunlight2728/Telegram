#import "TGGlobalMessageSearchSignals.h"

#import <LegacyComponents/LegacyComponents.h>

#import "TGTelegraph.h"
#import "TGDatabase.h"
#import "TGTelegramNetworking.h"
#import "TL/TLMetaScheme.h"
#import "TGUserDataRequestBuilder.h"
#import "TGConversation+Telegraph.h"
#import "TGMessage+Telegraph.h"

#import "TGRecentHashtagsSignal.h"

#import "TGDialogListRecentPeers.h"

#import "TGRecentPeersSignals.h"

#import "TGRemoteRecentPeer.h"
#import "TGRemoteRecentPeerSet.h"
#import "TGRemoteRecentPeerCategories.h"

#import "TGChannelAdminRights+Telegraph.h"
#import "TGChannelBannedRights+Telegraph.h"

#import "TLRPCmessages_search.h"
#import "TLRPCchannels_searchFeed.h"
#import "TLChat$channel.h"

NSString *const TGRecentSearchDefaultsKey = @"Telegram_recentSearch_peers";
const NSInteger TGRecentSearchLimit = 20;

@implementation TGGlobalMessageSearchSignals

+ (SSignal *)search:(NSString *)query includeMessages:(bool)includeMessages itemMapping:(id (^)(id))itemMapping
{
    if ([query isEqualToString:@"#"] && includeMessages)
    {
        return [[TGRecentHashtagsSignal recentHashtagsFromSpaces:TGHashtagSpaceEntered | TGHashtagSpaceSearchedBy] map:^id (NSArray *recentHashtags)
        {
            return @{@"hashtags": recentHashtags == nil ? @[] : recentHashtags};
        }];
    }
    else
    {
        SSignal *searchDialogsSignal = [[self searchDialogs:query] map:^id (NSDictionary *dict)
        {
            NSMutableArray *result = [[NSMutableArray alloc] init];
            
            for (id item in dict[@"chats"])
            {
                id mappedItem = itemMapping(item);
                if (mappedItem != nil)
                    [result addObject:mappedItem];
            }
            
            for (id item in dict[@"users"])
            {
                id mappedItem = itemMapping(item);
                if (mappedItem != nil)
                    [result addObject:mappedItem];
            }
            
            return result;
        }];
        
        SSignal *searchUsersSignal = [[[self searchUsersAndChannels:query] deliverOn:[SQueue wrapConcurrentNativeQueue:[TGDatabaseInstance() databaseQueue]]] map:^id (NSDictionary *results)
        {
            NSMutableArray *myResult = [[NSMutableArray alloc] init];
            for (id item in results[@"myPeers"])
            {
                id mappedItem = itemMapping(item);
                if (mappedItem != nil)
                    [myResult addObject:mappedItem];
            }
            
            NSMutableArray *result = [[NSMutableArray alloc] init];
            for (id item in results[@"peers"])
            {
                id mappedItem = itemMapping(item);
                if (mappedItem != nil)
                    [result addObject:mappedItem];
            }
            
            return @{ @"myResult": myResult, @"result": result };
        }];
        
        SSignal *searchMessagesSignal = [SSignal single:@[]];
        
        if (includeMessages)
        {
            searchMessagesSignal = [[[self searchMessages:query peerId:0 accessHash:0 userId:0 maxId:0 limit:100] deliverOn:[SQueue wrapConcurrentNativeQueue:[TGDatabaseInstance() databaseQueue]]] map:^id (NSArray *conversations)
            {
                NSMutableArray *result = [[NSMutableArray alloc] init];
                for (id item in conversations)
                {
                    id mappedItem = itemMapping(item);
                    if (mappedItem != nil)
                        [result addObject:mappedItem];
                }
                
                [result sortUsingComparator:^NSComparisonResult(TGConversation *conversation1, TGConversation *conversation2)
                {
                    return conversation1.date > conversation2.date ? NSOrderedAscending : NSOrderedDescending;
                }];
                
                return result;
            }];
        }
        
        return [[SSignal combineSignals:@[searchDialogsSignal, searchUsersSignal, searchMessagesSignal]] map:^id (NSArray *results)
        {
            NSMutableArray *localResults = [[NSMutableArray alloc] initWithArray:results[0]];
            NSArray *additionalLocal = results[1][@"myResult"];
            for (NSUInteger i = 0; i < additionalLocal.count; i++)
            {
                int64_t peerId = 0;
                if ([additionalLocal[i] isKindOfClass:[TGUser class]]) {
                    peerId = ((TGUser *)additionalLocal[i]).uid;
                } else if ([additionalLocal[i] isKindOfClass:[TGConversation class]]) {
                    peerId = ((TGConversation *)additionalLocal[i]).conversationId;
                }
                
                bool found = false;
                
                for (id item in localResults)
                {
                    if ([item isKindOfClass:[TGConversation class]])
                    {
                        if (((TGConversation *)item).conversationId == peerId || ((TGConversation *)item).conversationId == TGTelegraphInstance.clientUserId)
                        {
                            found = true;
                            break;
                        }
                    }
                    else if ([item isKindOfClass:[TGUser class]])
                    {
                        if (((TGUser *)item).uid == peerId || ((TGUser *)item).uid == TGTelegraphInstance.clientUserId)
                        {
                            found = true;
                            break;
                        }
                    }
                }
                
                if (!found)
                    [localResults addObject:additionalLocal[i]];
            }
            
            NSArray *global = results[1][@"result"];
            NSMutableArray *globalResults = [[NSMutableArray alloc] initWithArray:global];
            for (NSUInteger i = 0; i < globalResults.count; i++)
            {
                int64_t peerId = 0;
                if ([globalResults[i] isKindOfClass:[TGUser class]]) {
                    peerId = ((TGUser *)globalResults[i]).uid;
                } else if ([globalResults[i] isKindOfClass:[TGConversation class]]) {
                    peerId = ((TGConversation *)globalResults[i]).conversationId;
                }
                
                bool found = false;
                
                for (id item in localResults)
                {
                    if ([item isKindOfClass:[TGConversation class]])
                    {
                        if (((TGConversation *)item).conversationId == peerId || ((TGConversation *)item).conversationId == TGTelegraphInstance.clientUserId)
                        {
                            found = true;
                            break;
                        }
                    }
                    else if ([item isKindOfClass:[TGUser class]])
                    {
                        if (((TGUser *)item).uid == peerId || ((TGUser *)item).uid == TGTelegraphInstance.clientUserId)
                        {
                            found = true;
                            break;
                        }
                    }
                }
                
                if (found)
                {
                    [globalResults removeObjectAtIndex:i];
                    i--;
                }
            }
            return @{@"dialogs": localResults, @"global": globalResults, @"messages": results[2]};
        }];
    }
}

+ (SSignal *)searchMessages:(NSString *)query peerId:(int64_t)peerId accessHash:(int64_t)accessHash userId:(int32_t)userId maxId:(int32_t)maxId limit:(int32_t)limit itemMapping:(id (^)(id))itemMapping
{
    return [[[self searchMessages:query peerId:peerId accessHash:accessHash userId:userId maxId:maxId limit:limit] deliverOn:[SQueue wrapConcurrentNativeQueue:[TGDatabaseInstance() databaseQueue]]] map:^id (NSArray *conversations)
    {
        NSMutableArray *result = [[NSMutableArray alloc] init];
        for (id item in conversations)
        {
            id mappedItem = itemMapping(item);
            if (mappedItem != nil)
                [result addObject:mappedItem];
        }
        
        [result sortUsingComparator:^NSComparisonResult(TGConversation *conversation1, TGConversation *conversation2)
        {
            return conversation1.date > conversation2.date ? NSOrderedAscending : NSOrderedDescending;
        }];
        
        return result;
    }];
}

+ (SSignal *)searchDialogs:(NSString *)query itemMapping:(id (^)(id))itemMapping {
    return [[self searchDialogs:query] map:^id (NSDictionary *dict) {
        NSMutableArray *result = [[NSMutableArray alloc] init];
        
        for (id item in dict[@"chats"]) {
            id mappedItem = itemMapping(item);
            if (mappedItem != nil) {
                [result addObject:mappedItem];
            }
        }
        
        for (id item in dict[@"users"]) {
            id mappedItem = itemMapping(item);
            if (mappedItem != nil) {
                [result addObject:mappedItem];
            }
        }
        
        return result;
    }];
}

+ (SSignal *)searchDialogs:(NSString *)query
{
    return [[SSignal alloc] initWithGenerator:^(SSubscriber *subscriber)
    {
        __block bool isCancelled = false;
        [TGDatabaseInstance() searchDialogs:query ignoreUid:TGTelegraphInstance.clientUserId partial:true completion:^(NSDictionary *dict, bool isFinal)
        {
            [subscriber putNext:dict];
            if (isFinal)
                [subscriber putCompletion];
        } isCancelled:^bool
        {
            return isCancelled;
        }];
        
        return [[SBlockDisposable alloc] initWithBlock:^
        {
            isCancelled = true;
        }];
    }];
}

+ (SSignal *)searchUsersAndChannels:(NSString *)query
{
    TLRPCcontacts_search$contacts_search *search = [[TLRPCcontacts_search$contacts_search alloc] init];
    search.q = query;
    search.limit = 32;
    SSignal *remoteSignal = [[[[TGTelegramNetworking instance] requestSignal:search] delay:0.15 onQueue:[SQueue concurrentDefaultQueue]] map:^id(TLcontacts_Found *result)
    {
        [TGUserDataRequestBuilder executeUserDataUpdate:result.users];
        
        NSMutableArray<TGConversation *> *conversations = [[NSMutableArray alloc] init];
        NSMutableDictionary *channels = [[NSMutableDictionary alloc] init];
        for (TLChat *chat in result.chats) {
            TGConversation *conversation = [[TGConversation alloc] initWithTelegraphChatDesc:chat];
            if (conversation.isChannel) {
                channels[@(conversation.conversationId)] = (TLChat$channel *)chat;
                [conversations addObject:conversation];
            }
        }
        
        [TGDatabaseInstance() updateChannels:conversations];
        
        NSMutableArray *myPeers = [[NSMutableArray alloc] init];
        for (TLPeer *peer in result.my_results)
        {
            if ([peer isKindOfClass:[TLPeer$peerUser class]]) {
                TGUser *user = [TGDatabaseInstance() loadUser:((TLPeer$peerUser *)peer).user_id];
                if (user != nil)
                    [myPeers addObject:user];
            } else if ([peer isKindOfClass:[TLPeer$peerChannel class]]) {
                TLPeer$peerChannel *peerChannel = (TLPeer$peerChannel *)peer;
                int64_t peerId = TGPeerIdFromChannelId(peerChannel.channel_id);
                TGConversation *conversation = [TGDatabaseInstance() loadChannels:@[@(peerId)]][@(peerId)];
                conversation.chatParticipantCount = [channels[@(peerId)] participants_count];
                if (conversation != nil) {
                    [myPeers addObject:conversation];
                }
            }
        }
        
        NSMutableArray *peers = [[NSMutableArray alloc] init];
        for (TLPeer *peer in result.results)
        {
            if ([peer isKindOfClass:[TLPeer$peerUser class]]) {
                TGUser *user = [TGDatabaseInstance() loadUser:((TLPeer$peerUser *)peer).user_id];
                if (user != nil)
                    [peers addObject:user];
            } else if ([peer isKindOfClass:[TLPeer$peerChannel class]]) {
                TLPeer$peerChannel *peerChannel = (TLPeer$peerChannel *)peer;
                int64_t peerId = TGPeerIdFromChannelId(peerChannel.channel_id);
                TGConversation *conversation = [TGDatabaseInstance() loadChannels:@[@(peerId)]][@(peerId)];
                conversation.chatParticipantCount = [channels[@(peerId)] participants_count];
                if (conversation != nil) {
                    [peers addObject:conversation];
                }
            }
        }
        
        return @{ @"myPeers": myPeers, @"peers": peers };
    }];
    
    if (query.length < 3)
        return [SSignal single:@{@"myPeers": @[], @"peers": @[]}];
    else
        return [[SSignal single:@{@"myPeers": @[], @"peers": @[]}] then:remoteSignal];
}

+ (SSignal *)searchMessages:(NSString *)query peerId:(int64_t)peerId accessHash:(int64_t)accessHash userId:(int32_t)userId maxId:(int32_t)maxId limit:(int32_t)limit
{
    SSignal *(^remoteSignalGenerator)(NSSet *) = ^SSignal *(NSSet *currentMessageIds)
    {
        id requestBody = nil;
        
        if (peerId == 0) {
            TLRPCmessages_searchGlobal$messages_searchGlobal *searchGlobal = [[TLRPCmessages_searchGlobal$messages_searchGlobal alloc] init];
            searchGlobal.q = query;
            searchGlobal.offset_date = 0;
            searchGlobal.offset_id = maxId;
            searchGlobal.offset_peer = [[TLInputPeer$inputPeerEmpty alloc] init];
            searchGlobal.limit = limit;
            
            requestBody = searchGlobal;
        } else if (TGPeerIdIsAdminLog(peerId)) {
            TLRPCchannels_searchFeed *searchFeed = [[TLRPCchannels_searchFeed alloc] init];
            searchFeed.feed_id = TGAdminLogIdFromPeerId(peerId);
            searchFeed.q = query;
            searchFeed.offset_date = 0;
            searchFeed.offset_id = maxId;
            searchFeed.offset_peer = [[TLInputPeer$inputPeerEmpty alloc] init];
            searchFeed.limit = limit;
            
            requestBody = searchFeed;
        } else {
            TLRPCmessages_search *search = [[TLRPCmessages_search alloc] init];
            search.peer = [TGTelegraphInstance createInputPeerForConversation:peerId accessHash:accessHash];
            
            search.q = query;
            if (query.length == 0) {
                search.q = @"";
            }
            
            search.filter = [[TLMessagesFilter$inputMessagesFilterEmpty alloc] init];
            search.min_date = 0;
            search.max_date = 0;
            search.offset = 0;
            search.limit = limit;
            search.max_id = maxId;
            if (userId != 0) {
                search.from_id = [TGTelegraphInstance createInputUserForUid:userId];
                search.flags |= (1 << 0);
            }
            requestBody = search;
        }
        
        SSignal *requestSignal = [[[TGTelegramNetworking instance] requestSignal:requestBody] map:^id(TLmessages_Messages *result)
        {
            [TGUserDataRequestBuilder executeUserDataUpdate:result.users];
            
            NSMutableSet *messageIdsSet = [[NSMutableSet alloc] initWithSet:currentMessageIds];
            
            NSMutableArray *combinedResults = [[NSMutableArray alloc] init];
            
            NSMutableDictionary *chats = [[NSMutableDictionary alloc] init];
            
            NSMutableArray *channels = [[NSMutableArray alloc] init];
            for (TLChat *chatDesc in result.chats)
            {
                TGConversation *conversation = [[TGConversation alloc] initWithTelegraphChatDesc:chatDesc];
                if (conversation != nil)
                {
                    [chats setObject:conversation forKey:[[NSNumber alloc] initWithLongLong:conversation.conversationId]];
                    
                    if (conversation.isChannel) {
                        [channels addObject:conversation];
                    }
                }
            }
            
            [TGDatabaseInstance() updateChannels:channels];
            
            NSUInteger totalCount = result.messages.count;
            if ([result isKindOfClass:[TLmessages_Messages$messages_messagesSlice class]]) {
                totalCount = ((TLmessages_Messages$messages_messagesSlice *)result).count;
            } else if ([result isKindOfClass:[TLmessages_Messages$messages_channelMessages class]]) {
                totalCount = ((TLmessages_Messages$messages_channelMessages *)result).count;
            }
            
            for (TLMessage *messageDesc in result.messages)
            {
                TGMessage *message = [[TGMessage alloc] initWithTelegraphMessageDesc:messageDesc];
                if (message.mid != 0)
                {
                    if (![messageIdsSet containsObject:@(message.mid)])
                    {
                        [messageIdsSet addObject:@(message.mid)];
                        
                        TGConversation *conversation = nil;
                        if (message.cid < 0)
                            conversation = [chats[@(message.cid)] copy];
                        else
                        {
                            conversation = [[TGConversation alloc] init];
                            conversation.conversationId = message.cid;
                        }
                        
                        if (conversation != nil && !conversation.isDeactivated)
                        {
                            [conversation mergeMessage:message];
                            conversation.additionalProperties = @{@"searchMessageId": @(message.mid), @"totalCount": @(totalCount)};
                            [combinedResults addObject:conversation];
                        }
                    }
                }
            }
            
            return combinedResults;
        }];
        
        if (query.length < 1 && userId == 0)
            return [SSignal complete];
        else
        {
            return [requestSignal catch:^SSignal *(__unused id error)
            {
                return [SSignal complete];
            }];
        }
    };
    
    SSignal *combinedSignal = [[[SSignal alloc] initWithGenerator:^id<SDisposable> (SSubscriber *subscriber)
    {
        SMetaDisposable *disposable = [[SMetaDisposable alloc] init];
        
        if (peerId != 0 && TGPeerIdIsSecretChat(peerId)) {
            dispatch_block_t cancelBlock = [TGDatabaseInstance() searchMessages:query peerId:peerId completion:^(NSArray *result, NSSet *midsSet)
            {
                [subscriber putNext:result];
                
                [disposable setDisposable:[[remoteSignalGenerator(midsSet) delay:0.1 onQueue:[SQueue concurrentDefaultQueue]] startWithNext:^(NSArray *remoteResult)
                {
                    NSMutableArray *combinedResult = [[NSMutableArray alloc] initWithArray:result];
                    [combinedResult addObjectsFromArray:remoteResult];
                    [subscriber putNext:combinedResult];
                } error:^(id error)
                {
                    [subscriber putError:error];
                } completed:^
                {
                    [subscriber putCompletion];
                }]];
            }];
            
            [disposable setDisposable:[[SBlockDisposable alloc] initWithBlock:^
            {
                if (cancelBlock)
                    cancelBlock();
            }]];
            return disposable;
        } else {
            [disposable setDisposable:[[remoteSignalGenerator([NSSet set]) delay:0.1 onQueue:[SQueue concurrentDefaultQueue]] startWithNext:^(NSArray *remoteResult)
            {
                NSMutableArray *combinedResult = [[NSMutableArray alloc] init];
                [combinedResult addObjectsFromArray:remoteResult];
                [subscriber putNext:combinedResult];
            } error:^(id error)
            {
                [subscriber putError:error];
            } completed:^
            {
                [subscriber putCompletion];
            }]];
            return disposable;
        }
    }] delay:0.1 onQueue:[SQueue concurrentDefaultQueue]];
    
    if (maxId == 0) {
        return [[SSignal single:@[]] then:combinedSignal];
    } else {
        return combinedSignal;
    }
}

+ (void)moveRecentToContainer
{
    if (iosMajorVersion() < 8)
        return;
    
    NSUserDefaults *localDefaults = [NSUserDefaults standardUserDefaults];
    NSUserDefaults *containerDefaults = [self _containerDefaults];
    
    NSArray *localItems = [localDefaults objectForKey:TGRecentSearchDefaultsKey];
    if (localItems.count > 0)
    {
        [containerDefaults setObject:localItems forKey:TGRecentSearchDefaultsKey];
        [containerDefaults synchronize];
        
        [localDefaults removeObjectForKey:TGRecentSearchDefaultsKey];
        [localDefaults synchronize];
    }
}

+ (NSUserDefaults *)userDefaults
{
    static dispatch_once_t onceToken;
    static NSUserDefaults *userDefaults;
    dispatch_once(&onceToken, ^
    {
        if (iosMajorVersion() >= 8)
        {
            userDefaults = [self _containerDefaults];
            [self moveRecentToContainer];
        }
        else
        {
            userDefaults = [NSUserDefaults standardUserDefaults];;
        }
    });
    return userDefaults;
}

+ (NSUserDefaults *)_containerDefaults
{
    return [[NSUserDefaults alloc] initWithSuiteName:[@"group." stringByAppendingString:[[NSBundle mainBundle] bundleIdentifier]]];
}

+ (void)clearRecentResults
{
    [[self userDefaults] removeObjectForKey:TGRecentSearchDefaultsKey];
    [[self userDefaults] synchronize];
}

+ (void)addRecentPeerResult:(int64_t)peerId
{
    NSMutableArray *items = [[NSMutableArray alloc] initWithArray:[[self userDefaults] objectForKey:TGRecentSearchDefaultsKey]];
    [items removeObject:@(peerId)];
    [items insertObject:@(peerId) atIndex:0];
    if (items.count > TGRecentSearchLimit)
        [items removeObjectsInRange:NSMakeRange(TGRecentSearchLimit, items.count - TGRecentSearchLimit)];
    [[self userDefaults] setObject:items forKey:TGRecentSearchDefaultsKey];
    [[self userDefaults] synchronize];
}

+ (void)removeRecentPeerResult:(int64_t)peerId
{
    NSMutableArray *items = [[NSMutableArray alloc] initWithArray:[[self userDefaults] objectForKey:TGRecentSearchDefaultsKey]];
    [items removeObject:@(peerId)];
    [[self userDefaults] setObject:items forKey:TGRecentSearchDefaultsKey];
    [[self userDefaults] synchronize];
}

+ (NSString *)titleForCategory:(TGPeerRatingCategory)category {
    switch (category) {
        case TGPeerRatingCategoryPeople:
            return TGLocalized(@"DialogList.RecentTitlePeople");
        case TGPeerRatingCategoryGroups:
            return TGLocalized(@"DialogList.RecentTitleGroups");
        case TGPeerRatingCategoryBots:
            return TGLocalized(@"DialogList.RecentTitleBots");
        case TGPeerRatingCategoryNone:
            return nil;
        case TGPeerRatingCategoryInlineBots:
            return nil;
    }
}

+ (SSignal *)recentPeerResults:(id (^)(id, bool))itemMapping ratedPeers:(bool)ratedPeers
{
    return [[[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber)
    {
        NSArray *array = [[self userDefaults] objectForKey:TGRecentSearchDefaultsKey];
        NSMutableArray *peers = [[NSMutableArray alloc] init];
        for (NSNumber *nPeerId in array)
        {
            int64_t peerId = (int64_t)[nPeerId longLongValue];
            TGConversation *conversation = [TGDatabaseInstance() loadConversationWithId:peerId];
            if (conversation != nil)
            {
                if (conversation.isDeactivated) {
                    continue;
                }
                
                id item = itemMapping(conversation, true);
                if (item != nil)
                    [peers addObject:item];
            }
            
            if (conversation == nil)
            {
                TGUser *user = [TGDatabaseInstance() loadUser:(int)peerId];
                if (user != nil)
                    [peers addObject:user];
            }
        }
        
        [subscriber putNext:peers];
        [subscriber putCompletion];
        
        return nil;
    }] mapToSignal:^SSignal *(NSArray *peers) {
        if (ratedPeers) {
            return [[TGRecentPeersSignals recentPeers] mapToSignal:^id(TGRemoteRecentPeerCategories *categories) {
                return [TGDatabaseInstance() modify:^id{
                    NSMutableDictionary *parsedCategories = [[NSMutableDictionary alloc] init];
                    
                    [categories.categories enumerateKeysAndObjectsUsingBlock:^(NSNumber *category, TGRemoteRecentPeerSet *peers, __unused BOOL *stop) {
                        NSMutableArray *parsedPeers = [[NSMutableArray alloc] init];
                        
                        for (TGRemoteRecentPeer *peer in [peers.peers sortedArrayUsingComparator:^NSComparisonResult(TGRemoteRecentPeer *lhs, TGRemoteRecentPeer *rhs) {
                            return lhs.rating > rhs.rating ? NSOrderedAscending : NSOrderedDescending;
                        }]) {
                            TGConversation *conversation = [TGDatabaseInstance() loadConversationWithId:peer.peerId];
                            if (conversation != nil) {
                                if (conversation.isDeactivated) {
                                    continue;
                                }
                                
                                id item = itemMapping(conversation, false);
                                if (item != nil) {
                                    if (TGPeerIdIsUser(conversation.conversationId)) {
                                        TGUser *user = [TGDatabaseInstance() loadUser:(int)conversation.conversationId];
                                        if (user != nil) {
                                            [parsedPeers addObject:user];
                                        }
                                    } else {
                                        [parsedPeers addObject:item];
                                    }
                                }
                            }
                            
                            if (conversation == nil) {
                                TGUser *user = [TGDatabaseInstance() loadUser:(int)peer.peerId];
                                if (user != nil) {
                                    [parsedPeers addObject:user];
                                }
                            }
                        }
                        
                        parsedCategories[category] = [[TGDialogListRecentPeers alloc] initWithIdentifier:[NSString stringWithFormat:@"%d", [category intValue]] title:[self titleForCategory:[category intValue]] peers:parsedPeers];
                    }];
                    
                    NSMutableArray *result = [[NSMutableArray alloc] init];
                    
                    NSArray *categoryOrder = @[@(TGPeerRatingCategoryPeople)/*, @(TGPeerRatingCategoryGroups), @(TGPeerRatingCategoryBots)*/];
                    
                    for (NSNumber *category in categoryOrder) {
                        TGDialogListRecentPeers *parsedCategory = parsedCategories[category];
                        if (parsedCategory != nil && parsedCategory.peers.count != 0) {
                            [result addObject:parsedCategory];
                        }
                    }
                    
                    [result addObjectsFromArray:peers];
                    
                    return result;
                }];
            }];
        } else {
            return [SSignal single:peers];
        }
    }];
}

+ (SSignal *)searchChannelMembers:(NSString *)query peerId:(int64_t)peerId accessHash:(int64_t)accessHash section:(TGGlobalMessageSearchMembersSection)section {
    TLRPCchannels_getParticipants$channels_getParticipants *getParticipants = [[TLRPCchannels_getParticipants$channels_getParticipants alloc] init];
    TLInputChannel$inputChannel *inputChannel = [[TLInputChannel$inputChannel alloc] init];
    inputChannel.channel_id = TGChannelIdFromPeerId(peerId);
    inputChannel.access_hash = accessHash;
    getParticipants.channel = inputChannel;
    
    switch (section) {
        case TGGlobalMessageSearchMembersSectionMembers: {
            TLChannelParticipantsFilter$channelParticipantsSearch *filter = [[TLChannelParticipantsFilter$channelParticipantsSearch alloc] init];
            filter.q = query;
            getParticipants.filter = filter;
            break;
        }
        case TGGlobalMessageSearchMembersSectionBanned: {
            TLChannelParticipantsFilter$channelParticipantsKicked *filter = [[TLChannelParticipantsFilter$channelParticipantsKicked alloc] init];
            filter.q = query;
            getParticipants.filter = filter;
            break;
        }
        case TGGlobalMessageSearchMembersSectionRestricted: {
            TLChannelParticipantsFilter$channelParticipantsBanned *filter = [[TLChannelParticipantsFilter$channelParticipantsBanned alloc] init];
            filter.q = query;
            getParticipants.filter = filter;
            break;
        }
        default:
            break;
    }
    getParticipants.offset = 0;
    getParticipants.limit = 100;
    
    return [[[TGTelegramNetworking instance] requestSignal:getParticipants] mapToSignal:^SSignal *(TLchannels_ChannelParticipants *intermediateResult) {
        if ([intermediateResult isKindOfClass:[TLchannels_ChannelParticipants$channels_channelParticipants class]]) {
            TLchannels_ChannelParticipants$channels_channelParticipants *result = (TLchannels_ChannelParticipants$channels_channelParticipants *)intermediateResult;
            [TGUserDataRequestBuilder executeUserDataUpdate:result.users];
            
            NSMutableArray *users = [[NSMutableArray alloc] init];
            NSMutableDictionary *memberDatas = [[NSMutableDictionary alloc] init];
            
            for (TLChannelParticipant *participant in result.participants) {
                TGUser *user = [TGDatabaseInstance() loadUser:participant.user_id];
                if (user != nil) {
                    int32_t timestamp = 0;
                    bool isCreator = false;
                    TGChannelAdminRights *adminRights = nil;
                    TGChannelBannedRights *bannedRights = nil;
                    int32_t inviterId = 0;
                    int32_t adminInviterId = 0;
                    int32_t kickedById = 0;
                    bool adminCanManage = false;
                    
                    if ([participant isKindOfClass:[TLChannelParticipant$channelParticipant class]]) {
                        timestamp = ((TLChannelParticipant$channelParticipant *)participant).date;
                    } else if ([participant isKindOfClass:[TLChannelParticipant$channelParticipantCreator class]]) {
                        isCreator = true;
                        timestamp = 0;
                    } else if ([participant isKindOfClass:[TLChannelParticipant$channelParticipantAdmin class]]) {
                        adminRights = [[TGChannelAdminRights alloc] initWithTL:((TLChannelParticipant$channelParticipantAdmin *)participant).admin_rights];
                        inviterId = ((TLChannelParticipant$channelParticipantAdmin *)participant).inviter_id;
                        timestamp = ((TLChannelParticipant$channelParticipantAdmin *)participant).date;
                        adminInviterId = ((TLChannelParticipant$channelParticipantAdmin *)participant).promoted_by;
                        adminCanManage = ((TLChannelParticipant$channelParticipantAdmin *)participant).flags & (1 << 0);
                    } else if ([participant isKindOfClass:[TLChannelParticipant$channelParticipantBanned class]]) {
                        timestamp = ((TLChannelParticipant$channelParticipantBanned *)participant).date;
                        bannedRights = [[TGChannelBannedRights alloc] initWithTL:((TLChannelParticipant$channelParticipantBanned *)participant).banned_rights];
                        kickedById = ((TLChannelParticipant$channelParticipantBanned *)participant).kicked_by;
                    }
                    
                    memberDatas[@(user.uid)] = [[TGCachedConversationMember alloc] initWithUid:user.uid isCreator:isCreator adminRights:adminRights bannedRights:bannedRights timestamp:timestamp inviterId:inviterId adminInviterId:adminInviterId kickedById:kickedById adminCanManage:adminCanManage];
                    [users addObject:user];
                }
            }
            
            return [SSignal single:@{@"memberDatas": memberDatas, @"users": users}];
        } else {
            return [SSignal single:@{@"memberDatas": @{}, @"users": @[]}];
        }
    }];
}

+ (SSignal *)searchContacts:(NSString *)query {
    return [[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber) {
        [TGDatabaseInstance() searchContacts:query ignoreUid:TGTelegraphInstance.clientUserId searchPhonebook:false completion:^(NSDictionary *result) {
            [subscriber putNext:result[@"users"] ?: @[]];
        }];
        return nil;
    }];
}

@end
