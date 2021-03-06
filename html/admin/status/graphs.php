<?php
/**
 * TODO short desc
 *
 * TODO long desc
 * 
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,
 * USA.
 * 
 * @author      Dominik Gehl <dgehl@inverse.ca>
 * @copyright   2008-2010 Inverse inc.
 * @license     http://opensource.org/licenses/gpl-2.0.php      GPL
 */

  require_once('../common.php');
  require_once('grapher.php');

  $current_top="status";
  $current_sub="graphs";
  $is_printable=true;

  include_once('../header.php');

  $type = set_default($_GET['type'], 'nodes');
  $span = set_default($_GET['span'], 'day');

  $spanable = array('unregistered', 'violations', 'nodes');

  if(in_array($type, $spanable)){
    $pretty_type = pretty_header("$current_top-$current_sub", $type);
    if($span == 'day')
      $additional = "$pretty_type: <a href='$current_top/$current_sub.php?type=$type&span=day'><u>Daily</u></a> | <a href='$current_top/$current_sub.php?type=$type&span=month'>Monthly</a> | <a href='$current_top/$current_sub.php?type=$type&span=year'>Yearly</a>";
    else if($span == 'month')
      $additional = "$pretty_type: <a href='$current_top/$current_sub.php?type=$type&span=day'>Daily</a> | <a href='$current_top/$current_sub.php?type=$type&span=month'><u>Monthly</u></a> | <a href='$current_top/$current_sub.php?type=$type&span=year'>Yearly</a>";
    else
      $additional = "$pretty_type: <a href='$current_top/$current_sub.php?type=$type&span=day'>Daily</a> | <a href='$current_top/$current_sub.php?type=$type&span=month'>Monthly</a> | <a href='$current_top/$current_sub.php?type=$type&span=year'><u>Yearly</u></a>";
  }

  print helper_menu($current_top, $current_sub, $type, $_GET['menu'], $additional);

  if ($_REQUEST['type'] == 'traps') {
    if (! (file_exists('/usr/local/pf/html/admin/traplog/total_total.png'))) {
      print "<br><br><center><table class=\"main\">\n";
      print "<tr><td>No Results. Do you run `pfcmd traplog update` ?</td></tr>\n";
      print "</table></center>\n";
      include_once('../footer.php');
      exit(1);
    }
?>
<h3>All Switches</h3>
<table border="0">
<tr>
  <td><img src="/traplog/total_total.png"></td>
  <td><img src="/traplog/total_week.png"></td>
  <td><img src="/traplog/total_day.png"></td>
</tr>
</table>
<h3>3 Switches having the highest overall number of traps</h3>
<table border="0">
<?php
  $switch_lines = PFCMD("traplog most 3 total");
  $current_line = array_shift($switch_lines);
  foreach ($switch_lines as $current_line) {
    $pieces = explode('|', $current_line);
    $switch = $pieces[1];
    print "<tr>\n";
    print "  <td><img src=\"/traplog/{$switch}_total.png\" alt=\"[ $switch (Total) ]\"></td>\n";    
    print "  <td><img src=\"/traplog/{$switch}_week.png\" alt=\"[ $switch (Week) ]\"></td>\n";    
    print "  <td><img src=\"/traplog/{$switch}_day.png\" alt=\"[ $switch (Day) ]\"></td>\n";    
    print "</tr>\n";
  }
?>
</table>
<h3>3 Switches having the highest number of traps during the last week</h3>
<table border="0">
<?php
  $switch_lines = PFCMD("traplog most 3 week");
  $current_line = array_shift($switch_lines);
  foreach ($switch_lines as $current_line) {
    $pieces = explode('|', $current_line);
    $switch = $pieces[1];
    print "<tr>\n";
    print "  <td><img src=\"/traplog/{$switch}_total.png\" alt=\"[ $switch (Total) ]\"></td>\n";    
    print "  <td><img src=\"/traplog/{$switch}_week.png\" alt=\"[ $switch (Week) ]\"></td>\n";    
    print "  <td><img src=\"/traplog/{$switch}_day.png\" alt=\"[ $switch (Day) ]\"></td>\n";    
    print "</tr>\n";
  }
?>
</table>
<h3>3 Switches having the highest number of traps during the last day</h3>
<table border="0">
<?php
  $switch_lines = PFCMD("traplog most 3 day");
  $current_line = array_shift($switch_lines);
  foreach ($switch_lines as $current_line) {
    $pieces = explode('|', $current_line);
    $switch = $pieces[1];
    print "<tr>\n";
    print "  <td><img src=\"/traplog/{$switch}_total.png\" alt=\"[ $switch (Total) ]\"></td>\n";    
    print "  <td><img src=\"/traplog/{$switch}_week.png\" alt=\"[ $switch (Week) ]\"></td>\n";    
    print "  <td><img src=\"/traplog/{$switch}_day.png\" alt=\"[ $switch (Day) ]\"></td>\n";    
    print "</tr>\n";
  }
?>
</table>
<?php
  include_once('../footer.php');
  exit(1);
  }
  if (($_REQUEST['type'] != "ifoctetshistoryuser") && ($_REQUEST['type'] != "ifoctetshistorymac") && ($_REQUEST['type'] != "ifoctetshistoryswitch")) {
    jsgraph(array('type' => $type, 'span' => $span));
  } elseif ($_REQUEST['type'] == "ifoctetshistoryuser") {
?>
  <div id="history">
  <form action="<?=$current_top?>/<?=$current_sub?>.php?type=<?=$type?>&menu=<?=$_GET[menu]?>" name="history" method="post">
  <table class="main">
     <tr>
        <td rowspan=4 valign=top style="width: 70px"><img src='images/report.png'></td>
        <td>User</td>
        <td>
          <select name="pid">
<?php
$person_lines = PFCMD("person view all");
array_shift($person_lines);
foreach($person_lines as $current_person_line){
  $pieces = explode('|', $current_person_line);
  print "            <option value=\"" .$pieces[0] . "\"" . ($pieces[0] == $_REQUEST['pid'] ? " selected" : '') . ">" . $pieces[0] . (($pieces[1] != '') ? " (" . $pieces[1] . ")" : '') . "</option>\n";
}
                           
?>
          </select>
        </td>
     </tr>
     <tr>
        <td>Start Date and Time</td>
        <td><input id='start_time' name="start_time" value="<?=$_REQUEST['start_time']?>"><button type="reset" id="button_time">...</button> <?php show_calendar_with_button('start_time', 'button_time') ?></td>
     </tr>
     <tr>
        <td>End Date and Time</td>
        <td><input id='end_time' name="end_time" value="<?=$_REQUEST['end_time']?>"><button type="reset" id="button_time1">...</button> <?php show_calendar_with_button('end_time', 'button_time1') ?></td>
     </tr>
     <tr>
        <td colspan="2" align="right"><input type="submit" value="Query IfOctets History"></td>
     </tr>
  </table>
  </form>
  </div>
  <?php

  if (isset($_REQUEST['pid']) && (strlen(trim($_REQUEST['pid'])) > 0)) {
    if ((isset($_REQUEST['start_time']) && (strlen(trim($_REQUEST['start_time'])) > 0)) &&
      (isset($_REQUEST['end_time']) && (strlen(trim($_REQUEST['end_time'])) > 0))) {
      jsgraph(array('type' => $type, 'pid' => $_REQUEST['pid'], 'start_time' => $_REQUEST['start_time'], 'end_time' => $_REQUEST['end_time']));
    }
    $get_args['pid'] = $_REQUEST['pid'];
    $get_args['start_time'] = $_REQUEST['start_time'];
    $get_args['end_time'] = $_REQUEST['end_time'];
  }
} elseif ($_REQUEST['type'] == "ifoctetshistorymac") {
?>
  <div id="history">
  <form action="<?=$current_top?>/<?=$current_sub?>.php?type=<?=$type?>&menu=<?=$_GET[menu]?>" name="history" method="post">
  <table class="main">
     <tr>
        <td rowspan=4 valign=top style="width:70px"><img src='images/report.png'></td>
        <td>MAC</td>
        <td><input type="text" name="pid" value='<?=$_REQUEST['pid']?>'></td>
     </tr>
     <tr>
        <td>Start Date and Time</td>
        <td><input id='start_time' name="start_time" value="<?=$_REQUEST['start_time']?>"><button type="reset" id="button_time">...</button> <?php show_calendar_with_button('start_time', 'button_time') ?></td>
     </tr>
     <tr>
        <td>End Date and Time</td>
        <td><input id='end_time' name="end_time" value="<?=$_REQUEST['end_time']?>"><button type="reset" id="button_time1">...</button> <?php show_calendar_with_button('end_time', 'button_time1') ?></td>
     </tr>
     <tr>
        <td colspan="2" align="right"><input type="submit" value="Query IfOctets History"></td>
     </tr>
  </table>
  </form>
  </div>
  <?php

  if (isset($_REQUEST['pid']) && (strlen(trim($_REQUEST['pid'])) > 0)) {
    if ((isset($_REQUEST['start_time']) && (strlen(trim($_REQUEST['start_time'])) > 0)) &&
      (isset($_REQUEST['end_time']) && (strlen(trim($_REQUEST['end_time'])) > 0))) {
      jsgraph(array('type' => $type, 'pid' => $_REQUEST['pid'], 'start_time' => $_REQUEST['start_time'], 'end_time' => $_REQUEST['end_time']));
    }
    $get_args['pid'] = $_REQUEST['pid'];
    $get_args['start_time'] = $_REQUEST['start_time'];
    $get_args['end_time'] = $_REQUEST['end_time'];
  }
} elseif ($_REQUEST['type'] == "ifoctetshistoryswitch") {
?>
  <div id="history">
  <form action="<?=$current_top?>/<?=$current_sub?>.php?type=<?=$type?>&menu=<?=$_GET[menu]?>" name="history" method="post">
  <table class="main">
     <tr>
        <td rowspan=5 valign=top style="width:70px"><img src='images/report.png'></td>
        <td>Switch</td>
        <td><input type="text" name="switch" value='<?=$_REQUEST['switch']?>'></td>
     </tr>
     <tr>
        <td>Port</td>
        <td><input type="text" name="port" value='<?=$_REQUEST['port']?>'></td>
     </tr>
     <tr>
        <td>Start Date and Time</td>
        <td><input id='start_time' name="start_time" value="<?=$_REQUEST['start_time']?>"><button type="reset" id="button_time">...</button> <?php show_calendar_with_button('start_time', 'button_time') ?></td>
     </tr>
     <tr>
        <td>End Date and Time</td>
        <td><input id='end_time' name="end_time" value="<?=$_REQUEST['end_time']?>"><button type="reset" id="button_time1">...</button> <?php show_calendar_with_button('end_time', 'button_time1') ?></td>
     </tr>
     <tr>
        <td colspan="2" align="right"><input type="submit" value="Query IfOctets History"></td>
     </tr>
  </table>
  </form>
  </div>
  <?php

    if (isset($_REQUEST['switch']) && (strlen(trim($_REQUEST['switch'])) > 0) && isset($_REQUEST['port']) && (strlen(trim($_REQUEST['port'])) > 0)) {
    if ((isset($_REQUEST['start_time']) && (strlen(trim($_REQUEST['start_time'])) > 0)) &&
      (isset($_REQUEST['end_time']) && (strlen(trim($_REQUEST['end_time'])) > 0))) {
      jsgraph(array('type' => $type, 'switch' => $_REQUEST['switch'], 'port' => $_REQUEST['port'], 'start_time' => $_REQUEST['start_time'], 'end_time' => $_REQUEST['end_time']));
    }
    $get_args['switch'] = $_REQUEST['switch'];
    $get_args['port'] = $_REQUEST['port'];
    $get_args['start_time'] = $_REQUEST['start_time'];
    $get_args['end_time'] = $_REQUEST['end_time'];
  }
}            


  include_once('../footer.php');

?>

