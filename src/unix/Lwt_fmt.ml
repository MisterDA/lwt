(* OCaml promise library
 * http://www.ocsigen.org/lwt
 * Copyright (C) 2018 Gabriel Radanne
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, with linking exceptions;
 * either version 2.1 of the License, or (at your option) any later
 * version. See COPYING file for details.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
 * 02111-1307, USA.
 *)

open Lwt.Infix

type formatter = {
  commit : unit -> unit Lwt.t ;
  fmt : Format.formatter ;
}

let write_pending ppft = ppft.commit ()
let flush ppft = Format.pp_print_flush ppft.fmt () ; ppft.commit ()

let make_formatter ~commit ~fmt () = { commit ; fmt }

(** Stream formatter *)

type order =
  | String of string * int * int
  | Flush

let make_stream () =
  let stream, push = Lwt_stream.create () in
  let out_string s i j =
    push @@ Some (String (s, i, j))
  and flush () =
    push @@ Some Flush
  in
  let fmt = Format.make_formatter out_string flush in
  (* Not sure about that one *)
  Gc.finalise (fun _ -> push None) fmt ;
  let commit () = Lwt.return_unit in
  stream, make_formatter ~commit ~fmt ()
          
(** Channel formatter *)

let write_order oc = function
  | String (s, i, j) ->
    Lwt_io.write_from_string_exactly oc s i j
  | Flush ->
    Lwt_io.flush oc

let rec write_orders oc queue =
  if Queue.is_empty queue then
    Lwt.return_unit
  else
    let o = Queue.pop queue in
    write_order oc o >>= fun () ->
    write_orders oc queue
      
let of_channel oc =
  let q = Queue.create () in
  let out_string s i j =
    Queue.push (String (s, i, j)) q
  and flush () =
    Queue.push Flush q
  in
  let fmt = Format.make_formatter out_string flush in
  let commit () = write_orders oc q in
  make_formatter ~commit ~fmt ()

(** Printing functions *)

let kfprintf k ppft fmt =
  Format.kfprintf (fun ppf -> k ppf @@ ppft.commit ()) ppft.fmt fmt
let ikfprintf k ppft fmt =
  Format.ikfprintf (fun ppf -> k ppf @@ Lwt.return_unit) ppft.fmt fmt

let fprintf ppft fmt =
  kfprintf (fun _ t -> t) ppft fmt
let ifprintf ppft fmt =
  ikfprintf (fun _ t -> t) ppft fmt

let stdout = of_channel Lwt_io.stdout
let stderr = of_channel Lwt_io.stdout

let printf fmt = fprintf stdout fmt
let eprintf fmt = fprintf stderr fmt