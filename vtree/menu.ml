open! Core

module Item = struct
  type t =
    { label : string
    ; action : string
    ; accel : string option
    }
  [@@deriving sexp_of, equal]

  let create ?accel ~label ~action () = { label; action; accel }

  (* The "scope.name" half of an action reference, with a radio's "::target" stripped:
     what the resolution walk checks, and what the runtime hands to GTK's action lookup.
     Total -- a reference with no "::" is its own reference. *)
  let action_reference t =
    match String.substr_index t.action ~pattern:"::" with
    | None -> t.action
    | Some i -> String.prefix t.action i
  ;;
end

type entry =
  | Item of Item.t
  | Section of
      { label : string option
      ; entries : entry list
      }
  | Submenu of
      { label : string
      ; entries : entry list
      }
[@@deriving sexp_of, equal]

type t = entry list [@@deriving sexp_of, equal]

let item ?accel ~label ~action () = Item (Item.create ?accel ~label ~action ())
let section ?label entries = Section { label; entries }
let submenu ~label entries = Submenu { label; entries }

(* Every "scope.name" any item references, depth-first, duplicates kept (the walk reports
   each offending item once and the caller dedupes if it cares). *)
let action_references t =
  let rec go acc = function
    | Item i -> Item.action_reference i :: acc
    | Section { entries; _ } | Submenu { entries; _ } -> List.fold entries ~init:acc ~f:go
  in
  List.rev (List.fold t ~init:[] ~f:go)
;;
