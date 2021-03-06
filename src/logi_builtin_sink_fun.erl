%% @copyright 2014-2016 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc A built-in sink which consumes log messages by an arbitrary user defined function
%%
%% The default layout is `logi_builtin_layout_default:new()'.
%%
%% == NOTE ==
%% This module is provided for debuging/testing purposes only.
%%
%% A sink is stored into a logi_channel's ETS.
%% Then it will be loaded every time a log message is issued.
%% Therefore if the write function (`write_fun/0') of the sink is a huge size anonymous function,
%% all log issuers which use the channel will have to pay a non negligible cost to load it.
%%
%% And there is no overload protection.
%%
%% == EXAMPLE ==
%% <pre lang="erlang">
%% > error_logger:tty(false). % Suppresses annoying warning outputs for brevity
%%
%% > WriteFun = fun (_, Format, Data) -> io:format("[CONSUMED] " ++ Format ++ "\n", Data) end.
%% > {ok, _} = logi_channel:install_sink(logi_builtin_sink_fun:new(foo, WriteFun), info).
%% > logi:info("hello world").
%% [CONSUMED] hello world
%% </pre>
%% @end
-module(logi_builtin_sink_fun).

-behaviour(logi_sink_writer).

%%----------------------------------------------------------------------------------------------------------------------
%% Exported API
%%----------------------------------------------------------------------------------------------------------------------
-export([new/2]).

-export_type([write_fun/0]).

%%----------------------------------------------------------------------------------------------------------------------
%% 'logi_sink_writer' Callback API
%%----------------------------------------------------------------------------------------------------------------------
-export([write/4, get_writee/1]).

%%----------------------------------------------------------------------------------------------------------------------
%% Types
%%----------------------------------------------------------------------------------------------------------------------
-type write_fun() :: fun ((logi_context:context(), io:format(), logi_layout:data()) -> logi_sink_writer:written_data()).
%% A function which is used to consume log messages issued by `logi'

%%----------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%----------------------------------------------------------------------------------------------------------------------
%% @doc Creats a new sink instance
-spec new(logi_sink:id(), write_fun()) -> logi_sink:sink().
new(Id, Fun) ->
    _ = erlang:is_function(Fun, 3) orelse error(badarg, [Fun]),
    logi_sink:from_writer(Id, logi_sink_writer:new(?MODULE, Fun)).

%%----------------------------------------------------------------------------------------------------------------------
%% 'logi_sink_writer' Callback Functions
%%----------------------------------------------------------------------------------------------------------------------
%% @private
write(Context, Format, Data, Fun) ->
    Fun(Context, Format, Data).

%% @private
get_writee(_) ->
    undefined.
