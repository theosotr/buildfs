(*
 * Copyright (c) 2018-2020 Thodoris Sotiropoulos
 *
 * This program is free software: you can redistribute it and/or modify  
 * it under the terms of the GNU General Public License as published by  
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but 
 * WITHOUT ANY WARRANTY; without even the implied warranty of 
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU 
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License 
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 *)


let adapt_effect resource effect =
  match effect with
  | Domains.Read    v
  | Domains.Touch   v -> v, Domains.Consumed resource
  | Domains.Write   v -> v, Domains.Modified resource
  | Domains.Create  v -> v, Domains.Produced resource
  | Domains.Remove  v -> v, Domains.Expunged resource
