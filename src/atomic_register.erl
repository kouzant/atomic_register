-module(atomic_register).

-behaviour(gen_server).

-include_lib("atomic_register/include/ar_def.hrl").

%% Public API
-export([start/0, start_link/0, write/3]).

%% Server API
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% write_attempt: {Key, Value, num_of_resp, seqs}
%% store: key, value, sequence number
%% majority: the majority of the quorum
-record(reg_state, {write_attempt :: {string(), string(), integer(), [integer()]},
		    state :: atom(),
		    store :: [{string(), string(), integer()}],
		    client :: {pid(), reference()},
		    majority :: integer()
		   }).

%% Public API
start() ->
    gen_server:start({local, ?REG_NAME}, ?MODULE, [], []).

start_link() ->
    gen_server:start_link({local, ?REG_NAME}, ?MODULE, [], []).

write(Key, Value, Client) ->
    gen_server:cast(?REG_NAME, {ar_write_init, Key, Value, Client}).

%% Callback functions
init(_Args) ->
    InitState = #reg_state{state=init,majority=1,store=[], client={}},
    {ok, InitState}.

terminate(normal, _State) ->
    ok;
terminate(Reason, _State) ->
    io:format("Atomic register ubnormal termination ~p~n", [Reason]).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

handle_info(Info, State) ->
    io:format("Atomic register wtf??? ~p~n", [Info]),
    {noreply, State}.

handle_call(_Msg, _From, State) ->
    {reply, reply, State}.

handle_cast({ar_write_init, Key, Value, Client}, State) ->
    %% Read from majority to get highest sequence number for that key
    beb:broadcast({ar_seq, Key, self()}),
    %% Init the state for this write attempt
    Attempt = {Key, Value, 0, []},
    NewState = State#reg_state{state=seq_reply, write_attempt = Attempt, client=Client},
    {noreply, NewState};

handle_cast({ar_seq, Key, From}, State) ->
    Store = State#reg_state.store,
    case get_value(Key, Store) of
	{ok, {_Key, _Value, Seq}} ->
	    gen_server:cast(From, {ar_seq_reply, Key, Seq});
	{not_found} ->
	    gen_server:cast(From, {ar_seq_reply, Key, 0})
    end,
    {noreply, State};

%% Wait for majority
handle_cast({ar_seq_reply, Key, Seq}, State) when State#reg_state.state =:= seq_reply ->
    io:format("Received sequence number: ~p~n", [Seq]),
    Majority = State#reg_state.majority,
    io:format("Majority is: ~p~n", [Majority]),
    {Key, Value, Resps, Seqs} = State#reg_state.write_attempt,
    io:format("For the key ~p, I have received so far ~p seq~n", [Key, Resps]),
    %% If num of sequence numbers received >= majority
    %% continue with the second phase
    NewSeqs = [Seq | Seqs],
    case Resps + 1 < Majority of
	true ->
	    {noreply, State#reg_state{write_attempt={Key, Value, Resps + 1, NewSeqs}}};
	false ->
	    %% Continue with the second phase
	    Sequence = lists:max(NewSeqs) + 1,
	    gen_server:cast(?REG_NAME, {ar_write_phase, Key, Value, Sequence}),
	    {noreply, State#reg_state{state=write_phase}}
    end;

handle_cast({ar_seq_reply, _, _}, State) ->
    io:format("Received sequence number reply but I have the quorum~n"),
    {noreply, State};

handle_cast({ar_write_phase, Key, Value, Sequence}, State)
  when State#reg_state.state =:= write_phase->
    io:format("I can continue writing {~p,~p} with seq num ~p~n", [Key, Value, Sequence]),
    %% bcast and wait for majority for the write request
    beb:broadcast({ar_write_req_quorum, Key, Value, Sequence, self()}),
    %% Update the record if present
    {noreply, State#reg_state{write_attempt={Key, Value, 0, []}}};

handle_cast({ar_write_req_quorum, Key, Value, Sequence, From}, State) ->
    Store = State#reg_state.store,
    case get_value(Key, Store) of
	{ok, {Key, _Value, Seq}} when Sequence > Seq ->
	    io:format("Replacing key: ~p with seq ~p~n", [Key, Sequence]),
	    NewStore = lists:keyreplace(Key, 1, Store, {Key, Value, Sequence}),
	    gen_server:cast(From, {ar_write_req_quorum_ack}),
	    {noreply, State#reg_state{store=NewStore}};
	{ok, {Key, _Value, Seq}} when Sequence =< Seq->
	    io:format("Ignoring key ~p~n", [Key]),
	    gen_server:cast(From, {ar_write_req_quorum_ack}),
	    {noreply, State};
	{not_found} ->
	    io:format("Adding key ~p with seq ~p~n", [Key, Sequence]),
	    NewStore = [{Key, Value, Sequence} | Store],
	    gen_server:cast(From, {ar_write_req_quorum_ack}),
	    {noreply, State#reg_state{store=NewStore}}
    end;

handle_cast({ar_write_req_quorum_ack}, State) when State#reg_state.state =:= write_phase ->
    io:format("ACK for writing~n"),
    Majority = State#reg_state.majority,
    {K, V, Resps, S} = State#reg_state.write_attempt,
    case Resps + 1 < Majority of
	true ->
	    {noreply, State#reg_state{write_attempt={K, V, Resps + 1, S}}};
	false ->
	    {Pid, Ref} = State#reg_state.client,
	    Pid ! {ar_write_complete, Ref},
	    {noreply, State#reg_state{state=init, write_attempt={}}}
    end;

handle_cast({ar_write_req_quorum_ack}, State) ->
    io:format("Received write ACK but I already have quorum~n"),
    {noreply, State}.
	    
%% Private functions
get_value(Key, [{Key, Value, Seq} | _Xs]) ->
    {ok, {Key, Value, Seq}};
get_value(Key, [{_, _, _} | Xs]) ->
    get_value(Key, Xs);
get_value(_Key, []) ->
    {not_found}.

