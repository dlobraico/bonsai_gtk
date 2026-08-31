open! Core
open Gtk_import

module type Value = sig
  type t

  val equal : t -> t -> bool
end

module type Extra = sig
  type t

  val create : unit -> t
end

module No_extra = struct
  type t = unit

  let create () = ()
end

module Make (V : Value) (E : Extra) = struct
  module Cache = Stdlib.Ephemeron.K1.Make (struct
      type t = Widget.t

      let equal = Gobject.same
      let hash = Stdlib.Hashtbl.hash
    end)

  type t =
    { mutable refused : V.t option
    ; mutable unreported : string option
    ; extra : E.t
    }

  let cache : t Cache.t = Cache.create 8

  let state w =
    match Cache.find_opt cache w with
    | Some st -> st
    | None ->
      let st = { refused = None; unreported = None; extra = E.create () } in
      Cache.replace cache w st;
      st
  ;;

  let extra w = (state w).extra

  (* [find_opt] rather than [state]: a widget that has never refused anything has no
     entry, and the patcher asks this of every widget of these kinds on every frame.
     Minting one here to find [None] in it was the shape all four copies had (final
     review, core M6), and in the text view's case the minted record was
     [{ stale = true }], so the next frame paid a whole-buffer read for a question nobody
     asked. *)
  let take_report w =
    match Cache.find_opt cache w with
    | None -> None
    | Some st ->
      (match st.unreported with
       | None -> None
       | Some message ->
         st.unreported <- None;
         Some message)
  ;;

  let already_refused st value =
    match st.refused with
    | None -> false
    | Some refused ->
      phys_equal refused value
      || (V.equal refused value
          &&
          (* Adoption. For a [string] value this is what turns a model that rebuilds an
             equal string every frame from an [O(len)] comparison into a pointer
             comparison; for an immediate it re-stores the same word. *)
          (st.refused <- Some value;
           true))
  ;;

  let refuse st value ~reason =
    st.refused <- Some value;
    st.unreported <- Some reason
  ;;

  let landed st = st.refused <- None

  let forget_refusal w =
    Option.iter (Cache.find_opt cache w) ~f:(fun st -> st.refused <- None)
  ;;
end
