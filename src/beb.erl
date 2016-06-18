-module(beb).

-behaviour(gen_server).

%% Public API
-export([start/0, start_link/0, broadcast/1, stop/0]).

%% Server API
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(beb_state, {
	  nodes :: [node()]
	 }).

-define(BEB_NAME, beb).

%% Public API
broadcast(Msg) ->
    gen_server:cast(?BEB_NAME, {bcast, Msg}).

stop() ->
    gen_server:stop(?BEB_NAME).

start() ->
    gen_server:start({local, ?BEB_NAME}, ?MODULE, [], []).

start_link() ->
    gen_server:start_link({local, ?BEB_NAME}, ?MODULE, [], []).

%% Callbacks
init(_Args) ->
    State = #beb_state{nodes = ['ble@finwe', 'bla@finwe']},
    {ok, State}.

terminate(normal, _State) ->
    ok;
terminate(Reason, _State) ->
    io:format("Node ~p terminated for reason: ~p~n", [self(), Reason]).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

handle_info(Info, State) ->
    io:format("beb wtf? ~p~n", [Info]),
    {noreply, State}.

handle_call(_Request, _From, State) ->
    {noreply, State}.

handle_cast({bcast, Msg}, State) ->
    io:format("Received request to bcast~n"),
    bcast(Msg, State),
    {noreply, State};
handle_cast({ar_seq, Key, From}, State) ->
    io:format("Received request for highest sequence number~n"),
    %% Inform Atomic Register
    send2ar({ar_seq, Key, From}),
    {noreply, State};
handle_cast({ar_write_req_quorum, Key, Value, Sequence, From}, State) ->
    io:format("Received write request!~n"),
    send2ar({ar_write_req_quorum, Key, Value, Sequence, From}),
    {noreply, State}.


%% Private functions
bcast(Msg, State) ->
    gen_server:abcast(State#beb_state.nodes, ?BEB_NAME, Msg).

send2ar(Msg) ->
    gen_server:cast(ar, Msg).
