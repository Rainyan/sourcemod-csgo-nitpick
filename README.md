# sourcemod-nt-nitpick
CSGO aim inaccuracy check via server plugin -- Sound beeps to differentiate aim and strafe mistakes etc.

### YouTube video example (please excuse the viewmodel swapping):

<a target="_blank" href="https://www.youtube.com/watch?v=XCA0KfqKmDc"><img src="https://img.youtube.com/vi/XCA0KfqKmDc/0.jpg" alt="https://img.youtube.com/vi/XCA0KfqKmDc/0.jpg" /></a>

### Client commands

Either type the relevant *sm_command* in console, or use the *!command* chat message format.<br />
For example: *sm_nitpick* in console, or *!nitpick* in chat.

```
sm_nitpick_help -- See the help screen for this plugin.
sm_nitpick -- Toggle the nitpick mode.

sm_nitpick_toggle -- Alias for sm_nitpick.
sm_nitpick_level -- Set the nitpick information level.
sm_nitpick_use_sound -- Whether to use sounds on nitpick message.
sm_nitpick_only_fails -- Whether to only notify on failed shooting.
sm_nitpick_strafe_threshold -- How much strafing inaccuracy is acceptable.
```

### Server cvars

```
sm_nitpick_version -- Version of this plugin. This is set automatically.
sm_nitpick_vel_threshold -- Max acceptable velocity considered as accurate aim.
sm_nitpick_ok_verbosity -- Whether to notify player of correct shots.
```
