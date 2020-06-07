type error_location = {
  e_line_number : int;
  e_start : int;
  e_end : int
}

let error_location lexbuf =
  let open Lexing in
  let pos1 = lexbuf.lex_start_p in
  let pos2 = lexbuf.lex_curr_p in
  let line1 = pos1.pos_lnum
  and start1 = pos1.pos_bol in
  {
    e_line_number = line1;
    e_start = pos1.pos_cnum - start1;
    e_end = pos2.pos_cnum - start1
  }

let string_of_error_location {e_line_number; e_start; e_end} =
  Printf.sprintf "error at line %d, characters %d-%d\n" e_line_number
    e_start e_end

type error = [
  | `SyntaxError of error_location
  | `UnterminatedString of int (* line number *)
  | `IntOverflow of (int * string) (* line number and offending string *)
]

type row = ([`Sparse of Types.sparse | `Dense of Types.dense ], error) result

let string_of_error = function
  | `SyntaxError err ->
    Printf.sprintf "syntax error: %s" (string_of_error_location err)

  | `UnterminatedString line ->
    Printf.sprintf "unterminated string on line %d" line

  | `IntOverflow (line, offending_string) ->
    Printf.sprintf "value %S on line %d cannot be represented as an integer"
      offending_string line

type row_seq = row Seq.t

let of_channel ~no_header ch =
  let lexbuf = Lexing.from_channel ch in
  try
    let h =
      if not no_header then
        Parser.header Lexer.header lexbuf
      else
        []
    in
    let open Seq in
    let rec row () =
      try
        match Parser.row Lexer.row lexbuf with
        | `EOF -> Nil
        | `Dense d -> Cons (Ok (`Dense d), row)
        | `Sparse s -> Cons (Ok (`Sparse s), row)
      with
        | Parsing.Parse_error ->
          Cons (Error (`SyntaxError (error_location lexbuf)), fun () -> Nil)
        | Lexer.UnterminatedString line ->
          Cons (Error (`UnterminatedString line), fun () -> Nil)
        | Lexer.IntOverflow line_and_offending_string ->
          Cons (Error (`IntOverflow line_and_offending_string), fun () -> Nil)
    in
    Ok (h, row)

  with
    | Parsing.Parse_error ->
      Error (`SyntaxError (error_location lexbuf))
    | Lexer.UnterminatedString line ->
      Error (`UnterminatedString line)
    | Lexer.IntOverflow line_and_offending_string ->
      Error (`IntOverflow line_and_offending_string)

let row_of_string string =
  let lexbuf = Lexing.from_string string in
  try
    `Ok (Parser.row_sans_nl Lexer.row lexbuf)
  with
    | Parsing.Parse_error ->
      `SyntaxError (error_location lexbuf)
    | Lexer.UnterminatedString line ->
      `UnterminatedString line
    | Lexer.IntOverflow line_and_offending_string ->
      `IntOverflow line_and_offending_string
