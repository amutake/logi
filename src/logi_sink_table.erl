%% @copyright 2014-2016 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc Sinks management table
%% @private
%% @end
-module(logi_sink_table).

%%----------------------------------------------------------------------------------------------------------------------
%% Exported API
%%----------------------------------------------------------------------------------------------------------------------
-export([new/1]).
-export([delete/1]).
-export([register/5]).
-export([deregister/3]).
-export([which_sinks/1]).
-export([select/4]).

-export_type([table/0]).
-export_type([select_result/0]).

%%----------------------------------------------------------------------------------------------------------------------
%% Types
%%----------------------------------------------------------------------------------------------------------------------
-type table() :: ets:tab().

-type select_result() :: [logi_sink_writer:writer()].
%% A result of {@link select/4} function

%%----------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%----------------------------------------------------------------------------------------------------------------------
%% @doc Creates a new table for `Channel'
-spec new(logi_channel:id()) -> table().
new(Channel) ->
    ets:new(Channel, [set, protected, {read_concurrency, true}, named_table]).

%% @doc Deletes the table `Table'
-spec delete(table()) -> ok.
delete(Table) ->
    _ = ets:delete(Table),
    ok.

%% @doc Registers an sink
-spec register(table(), logi_sink:id(), logi_sink_writer:writer(), logi_condition:condition(), logi_condition:condition()) -> ok.
register(Table, SinkId, Writer, NewCondition, OldCondition) ->
    {Added, _, Deleted} = diff(logi_condition:normalize(NewCondition),
                               logi_condition:normalize(OldCondition)),
    ok = insert_sink(Table, SinkId, Writer),
    ok = index_condition(Table, SinkId, Added),
    ok = deindex_condition(Table, SinkId, Deleted),
    ok.

%% @doc Deregisters an sink
-spec deregister(table(), logi_sink:id(), logi_condition:condition()) -> ok.
deregister(Table, SinkId, Condition) ->
    ok = deindex_condition(Table, SinkId, logi_condition:normalize(Condition)),
    ok = delete_sink(Table, SinkId),
    ok.

%% @doc Returns a list of existing sinks
-spec which_sinks(table()) -> [logi_sink:id()].
which_sinks(Table) ->
    [Id || {Id, _} <- ets:tab2list(Table), is_atom(Id)].

%% @doc Selects sinks that meet the condition
-spec select(table(), logi:severity(), atom(), module()) -> select_result().
select(Table, Severity, Application, Module) ->
    try
        SinkIds = select_id(Table, Severity, Application, Module),
        lists:filtermap(
          fun (SinkId) ->
                  case ets:lookup(Table, SinkId) of
                      []       -> false; % maybe uninstalled
                      [{_, V}] -> {true, V}
                  end
          end,
          SinkIds)
    catch
        error:badarg -> []
    end.

%%----------------------------------------------------------------------------------------------------------------------
%% Internal Functions
%%----------------------------------------------------------------------------------------------------------------------
-spec diff(A::list(), B::list()) -> {OnlyA::list(), Common::list(), OnlyB::list()}.
diff(A, B) ->
    As = ordsets:from_list(A),
    Bs = ordsets:from_list(B),
    {
      ordsets:to_list(ordsets:subtract(As, Bs)),
      ordsets:to_list(ordsets:intersection(As, Bs)),
      ordsets:to_list(ordsets:subtract(Bs, As))
    }.

-spec insert_sink(table(), logi_sink:id(), logi_sink_writer:writer()) -> ok.
insert_sink(Table, SinkId, Writer) ->
    E = {SinkId, Writer},
    _ = ets:insert(Table, E),
    ok.

-spec delete_sink(table(), logi_sink:id()) -> ok.
delete_sink(Table, SinkId) ->
    _ = ets:delete(Table, SinkId),
    ok.

-spec index_condition(table(), logi_sink:id(), logi_condition:normalized_condition()) -> ok.
index_condition(_Table, _SinkId, []) ->
    ok;
index_condition(Table, SinkId, [S | Condition]) when is_atom(S) ->
    ok = push_sink_id(Table, {S}, SinkId),
    index_condition(Table, SinkId, Condition);
index_condition(Table, SinkId, [{S, A} | Condition]) ->
    ok = increment_descendant_count(Table, {S}),
    ok = push_sink_id(Table, {S, A}, SinkId),
    index_condition(Table, SinkId, Condition);
index_condition(Table, SinkId, [{S, A, M} | Condition]) ->
    ok = increment_descendant_count(Table, {S}),
    ok = increment_descendant_count(Table, {S, A}),
    ok = push_sink_id(Table, {S, A, M}, SinkId),
    index_condition(Table, SinkId, Condition).

-spec deindex_condition(table(), logi_sink:id(), logi_condition:normalized_condition()) -> ok.
deindex_condition(_Table, _SinkId, []) ->
    ok;
deindex_condition(Table, SinkId, [S | Condition]) when is_atom(S) ->
    ok = pop_sink_id(Table, {S}, SinkId),
    deindex_condition(Table, SinkId, Condition);
deindex_condition(Table, SinkId, [{S, A} | Condition]) ->
    ok = decrement_descendant_count(Table, {S}),
    ok = pop_sink_id(Table, {S, A}, SinkId),
    deindex_condition(Table, SinkId, Condition);
deindex_condition(Table, SinkId, [{S, A, M} | Condition]) ->
    ok = decrement_descendant_count(Table, {S, A}),
    ok = decrement_descendant_count(Table, {S}),
    ok = pop_sink_id(Table, {S, A, M}, SinkId),
    deindex_condition(Table, SinkId, Condition).

-spec increment_descendant_count(table(), term()) -> ok.
increment_descendant_count(Table, Key) ->
    [Count | List] = fetch(Table, Key, [0]),
    _ = ets:insert(Table, {Key, [Count + 1 | List]}),
    ok.

-spec decrement_descendant_count(table(), term()) -> ok.
decrement_descendant_count(Table, Key) ->
    _ = case fetch(Table, Key) of
            [1]                           -> ets:delete(Table, Key);
            [Count | List] when Count > 0 -> ets:insert(Table, {Key, [Count - 1 | List]})
        end,
    ok.

-spec push_sink_id(table(), term(), logi_sink:id()) -> ok.
push_sink_id(Table, Key, SinkId) ->
    [DescendantCount | SinkIds] = fetch(Table, Key, [0]),
    _ = ets:insert(Table, {Key, [DescendantCount | lists:sort([SinkId | SinkIds])]}),
    ok.

-spec pop_sink_id(table(), term(), logi_sink:id()) -> ok.
pop_sink_id(Table, Key, SinkId) ->
    [DescendantCount | SinkIds0] = fetch(Table, Key, [0]),
    SinkIds1 = lists:delete(SinkId, SinkIds0),
    _ = case {DescendantCount, SinkIds1} of
            {0, []} -> ets:delete(Table, Key);
            _       -> ets:insert(Table, {Key, [DescendantCount | SinkIds1]})
        end,
    ok.

-spec fetch(table(), term()) -> term().
fetch(Table, Key) ->
    [{_, V}] = ets:lookup(Table, Key),
    V.

-spec fetch(table(), term(), term()) -> term().
fetch(Table, Key, Default) ->
    case ets:lookup(Table, Key) of
        []       -> Default;
        [{_, V}] -> V
    end.

-spec select_id(table(), logi:severity(), atom(), module()) -> [logi_sink:id()].
select_id(Table, Severity, Application, Module) ->
    case fetch(Table, {Severity}, [0]) of
        [0 | Ids0] -> Ids0;
        [_ | Ids0] ->
            case fetch(Table, {Severity, Application}, [0]) of
                [0 | Ids1] -> lists:umerge(Ids0, Ids1);
                [_ | Ids1] ->
                    [_ | Ids2] = fetch(Table, {Severity, Application, Module}, [0]),
                    lists:umerge([Ids0, Ids1, Ids2])
            end
    end.
