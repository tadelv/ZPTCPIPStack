//
//  ZPTCPConnection.m
//  ZPTCPIPStack
//
//  Created by ZapCannon87 on 11/08/2017.
//  Copyright © 2017 zapcannon87. All rights reserved.
//

#import "ZPTCPConnection.h"
#import "ZPTCPConnectionEx.h"
#import "ZPPacketTunnel.h"
#import "ZPPacketTunnelEx.h"

static void *IsOnTimerQueueKey = &IsOnTimerQueueKey; /* key to identify the queue */

err_t zp_tcp_sent(void *arg, struct tcp_pcb *tpcb, u16_t len)
{
    ZPTCPConnection *conn = (__bridge ZPTCPConnection *)(arg);
    LWIP_ASSERT("Must be dispatched on timer queue",
                dispatch_get_specific(IsOnTimerQueueKey) == (__bridge void *)(conn.timerQueue));
    LWIP_ASSERT("Must did set delegateQueue before sent data", conn.delegateQueue);
    dispatch_async(conn.delegateQueue, ^{
        if (conn.delegate) {
            [conn.delegate connection:conn didWriteData:len sendBuf:(tpcb->snd_buf == TCP_SND_BUF)];
        }
    });
    return ERR_OK;
}

err_t zp_tcp_recv(void *arg, struct tcp_pcb *tpcb, struct pbuf *p, err_t err)
{
    ZPTCPConnection *conn = (__bridge ZPTCPConnection *)(arg);
    LWIP_ASSERT("Must be dispatched on timer queue",
                dispatch_get_specific(IsOnTimerQueueKey) == (__bridge void *)(conn.timerQueue));
    if (conn.block->close_after_writing) {
        /* connection has closed, no longer recv data */
        return ERR_INPROGRESS;
    }
    if (p == NULL) {
        /* got FIN */
        if (conn.delegateQueue) {
            dispatch_async(conn.delegateQueue, ^{
                if (conn.delegate
                    && [conn.delegate respondsToSelector:@selector(connectionDidCloseReadStream:)])
                {
                    [conn.delegate connectionDidCloseReadStream:conn];
                }
            });
        }
        return ERR_OK;
    }
    if (conn.canReadData) {
        conn.canReadData = FALSE;
        void *buf = malloc(sizeof(char) * p->tot_len);
        LWIP_ASSERT("error in pbuf_copy_partial",
                    pbuf_copy_partial(p, buf, p->tot_len, 0) != 0);
        NSData *data = [NSData dataWithBytesNoCopy:buf length:p->tot_len];
        LWIP_ASSERT("Must did set delegateQueue before start read data", conn.delegateQueue);
        dispatch_async(conn.delegateQueue, ^{
            if (conn.delegate) {
                [conn.delegate connection:conn didReadData:data];
            }
        });
        pbuf_free(p);
        tcp_recved(tpcb, p->tot_len);
        return ERR_OK;
    } else {
        return ERR_INPROGRESS;
    }
}

err_t zp_tcp_connected(void *arg, struct tcp_pcb *tpcb, err_t err)
{
    ZPTCPConnection *conn = (__bridge ZPTCPConnection *)(arg);
    LWIP_ASSERT("Must be dispatched on timer queue",
                dispatch_get_specific(IsOnTimerQueueKey) == (__bridge void *)(conn.timerQueue));
    [conn.tunnel tcpConnectionEstablished:conn];
    return ERR_OK;
}

err_t zp_tcp_poll(void *arg, struct tcp_pcb *tpcb)
{
    return ERR_OK;
}

void zp_tcp_err(void *arg, err_t err)
{
    ZPTCPConnection *conn = (__bridge ZPTCPConnection *)(arg);
    LWIP_ASSERT("Must be dispatched on timer queue",
                dispatch_get_specific(IsOnTimerQueueKey) == (__bridge void *)(conn.timerQueue));
    NSString *errorDomain = NULL;
    if (err == ERR_ABRT) {
        /* Connection was aborted by local. */
        errorDomain = @"Connection was aborted by local.";
    } else if (err == ERR_RST) {
        /* Connection was reset by remote. */
        errorDomain = @"Connection was reset by remote.";
    } else if (err == ERR_CLSD) {
        /* Connection was successfully closed by remote. */
        errorDomain = @"Connection was successfully closed by remote.";
    } else {
        errorDomain = @"Unknown error.";
    }
    NSError *error = [NSError errorWithDomain:errorDomain code:err userInfo:NULL];
    if (conn.delegateQueue) {
        dispatch_async(conn.delegateQueue, ^{
            if (conn.delegate) {
                [conn.delegate connection:conn didDisconnectWithError:error];
            }
        });
    }
}


@implementation ZPTCPConnection

+ (instancetype)newTCPConnectionWith:(ZPPacketTunnel *)tunnel
                           identifie:(NSString *)identifie
                              ipData:(struct ip_globals *)ipData
                             tcpInfo:(struct tcp_info *)tcpInfo
                                pbuf:(struct pbuf *)pbuf
{
    return [[self alloc] initWithTunnel:tunnel
                              identifie:identifie
                                 ipData:ipData
                                tcpInfo:tcpInfo
                                   pbuf:pbuf];
}

- (instancetype)initWithTunnel:(ZPPacketTunnel *)tunnel
                     identifie:(NSString *)identifie
                        ipData:(struct ip_globals *)ipData
                       tcpInfo:(struct tcp_info *)tcpInfo
                          pbuf:(struct pbuf *)pbuf
{
    self = [super init];
    
    return self;
}

- (void)configSrcAddr:(NSString *)srcAddr
              srcPort:(UInt16)srcPort
             destAddr:(NSString *)destAddr
             destPort:(UInt16)destPort
{
    _srcAddr = srcAddr;
    _srcPort = srcPort;
    _destAddr = destAddr;
    _destPort = destPort;
}

- (void)tcpInputWith:(struct ip_globals)ipdata
             tcpInfo:(struct tcp_info)info
                pbuf:(struct pbuf *)pbuf
{
    dispatch_async(_timerQueue, ^{
        _block->ip_data = ipdata;
        _block->tcpInfo = info;
        tcp_input(pbuf, _block);
    });
}

// MARK: - API

- (BOOL)syncSetDelegate:(id<ZPTCPConnectionDelegate>)delegate delegateQueue:(dispatch_queue_t)queue
{
    NSAssert(dispatch_get_specific(IsOnTimerQueueKey) != (__bridge void *)(_timerQueue),
             @"Must not be dispatched on timer queue");
    __block BOOL pcb_is_valid;
    dispatch_sync(_timerQueue, ^{
        if (_block->pcb) {
            _delegate = delegate;
            if (queue) {
                _delegateQueue = queue;
            } else {
                _delegateQueue = dispatch_queue_create("ZPTCPConnection.delegateQueue", NULL);
            }
            pcb_is_valid = TRUE;
        } else {
            pcb_is_valid = FALSE;
        }
    });
    return pcb_is_valid;
}

- (void)asyncSetDelegate:(id<ZPTCPConnectionDelegate>)delegate delegateQueue:(dispatch_queue_t)queue
{
    dispatch_async(_timerQueue, ^{
        _delegate = delegate;
        if (queue) {
            _delegateQueue = queue;
        } else {
            _delegateQueue = dispatch_queue_create("ZPTCPConnection.delegateQueue", NULL);
        }
    });
}

- (void)write:(NSData *)data
{
    dispatch_async(_timerQueue, ^{
        struct tcp_pcb *pcb = _block->pcb;
        if (pcb == NULL || _block->close_after_writing) {
            return;
        }
        err_t err = tcp_write(pcb, data.bytes, data.length, TCP_WRITE_FLAG_COPY);
        if (err == ERR_OK) {
            tcp_output(pcb);
        } else {
            NSString *errDomain;
            if (err == ERR_CONN) {
                errDomain = @"Connection is in invalid state for data transmission.";
            } else if (err == ERR_MEM) {
                errDomain = @"Fail on too much data or there is not enough send buf space for data.";
            } else {
                errDomain = @"Unknown error.";
            }
            NSError *error = [NSError errorWithDomain:errDomain code:err userInfo:NULL];
            dispatch_async(_delegateQueue, ^{
                if (self.delegate) {
                    [self.delegate connection:self didCheckWriteDataWithError:error];
                }
            });
        }
    });
}

- (void)readData
{
    dispatch_async(_timerQueue, ^{
        struct tcp_pcb *pcb = _block->pcb;
        if (pcb == NULL) {
            return;
        }
        _canReadData = TRUE;
    });
}

- (void)close
{
    dispatch_async(_timerQueue, ^{
        struct tcp_pcb *pcb = _block->pcb;
        if (pcb == NULL) {
            return;
        }
        tcp_close(pcb);
    });
}

- (void)closeAfterWriting
{
    dispatch_async(_timerQueue, ^{
        _block->close_after_writing = 1;
    });
}

@end
