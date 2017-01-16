/* valanullconditionalexpression.vala
 *
 * Copyright (C) 2016  Jeeyong Um
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 * 	Jeeyong Um <conr2d@gmail.com>
 */

using GLib;

/**
 * Represents a null-conditional expression in the source code.
 */
public class Vala.NullConditionalExpression : Expression {
	/**
	 * The expression to be evaluated if all sub expressions are not null.
	 */
	public Expression inner {
		get {
			return _inner;
		}
		set {
			_inner = value;
			_inner.parent_node = this;
		}
	}

	/**
	 * The list of sub expressions which require null-check.
	 */
	public List<Expression> nullable_expressions {
		get {
			return _nullable_expressions;
		}
		set {
			_nullable_expressions = value;
		}
	}

	Expression _inner;
	List<Expression> _nullable_expressions = new ArrayList<Expression> ();

	/**
	 * Creates a new null-conditional expression.
	 *
	 * @param inner            expression to be evaluated if all sub expressions are not null
	 * @param source_reference reference to source code
	 * @return                 newly created null-conditional expression
	 */
	public NullConditionalExpression (Expression inner, SourceReference source_reference) {
		this.inner = inner;
		this.source_reference = source_reference;
	}

	/**
	 * Appends the specified expression which requires null-check to the list.
	 *
	 * @param expr an expression
	 */
	public void add_nullable_expression (Expression expr) {
		nullable_expressions.add (expr);
	}

	public override void accept (CodeVisitor visitor){
		visitor.visit_null_conditional_expression (this);

		visitor.visit_expression (this);
	}

	public override void accept_children (CodeVisitor visitor) {
		inner.accept (visitor);
	}

	public override bool is_pure () {
		return inner.is_pure ();
	}

	public override bool is_accessible (Symbol sym) {
		return inner.is_accessible (sym);
	}

	public override bool check (CodeContext context) {
		if (checked) {
			return !error;
		}

		checked = true;

		if (!(context.analyzer.current_symbol is Block)) {
			Report.error (source_reference, "Null-Conditional expressions may only be used in blocks");
			error = true;
			return false;
		}

		bool void_return_type = false;

		// To check return type of method call, create temporary ExpressionStatement
		ExpressionStatement stmt = null;

		var method_call = inner as MethodCall;
		if (method_call != null) {
			stmt = new ExpressionStatement (inner, inner.source_reference);
			inner.check (context);

			var mtype = method_call.call.value_type as MethodType;
			void_return_type = mtype.get_return_type () is VoidType;
		} else {
			inner.check (context);
		}

		var true_block = new Block (source_reference);

		LocalVariable local = null;
		DeclarationStatement decl = null;

		if (!void_return_type) {
			local = new LocalVariable (null, get_temp_name (), null, source_reference);
			decl = new DeclarationStatement (local, source_reference);

			value_type = inner.value_type.copy ();
			value_type.nullable = true;

			local.variable_type = value_type;
			decl.check (context);
			insert_statement (context.analyzer.insert_block, decl);

			stmt = new ExpressionStatement (new Assignment (new MemberAccess.simple (local.name, source_reference), inner, AssignmentOperator.SIMPLE, source_reference), source_reference);
		}
		true_block.add_statement (stmt);

		int index = nullable_expressions.size - 1;

		IfStatement if_stmt = null;
		LocalVariable inner_local = null;
		DeclarationStatement inner_decl = null;
		ExpressionStatement inner_stmt = null;

		while (index >= 0) {
			var ma = nullable_expressions[index] as MemberAccess;
			var ea = nullable_expressions[index] as ElementAccess;
			var se = nullable_expressions[index] as SliceExpression;

			Expression inner_expr = null;

			if (ma != null) {
				inner_expr = ma.inner;
			} else if (ea != null) {
				inner_expr = ea.container;
			} else if (se != null) {
				inner_expr = se.container;
			}

			inner_local = new LocalVariable (inner_expr.value_type, get_temp_name (), null, inner_expr.source_reference);
			inner_decl = new DeclarationStatement (inner_local, inner_expr.source_reference);
			inner_decl.check (context);

			inner_stmt = new ExpressionStatement (new Assignment (new MemberAccess.simple (inner_local.name, source_reference), inner_expr, AssignmentOperator.SIMPLE, inner_expr.source_reference), inner_expr.source_reference);
			inner_stmt.check (context);

			// For thread safety, assign null-conditional expression to local variable
			var inner_ma = new MemberAccess.simple (inner_local.name, inner_expr.source_reference);
			inner_ma.formal_target_type = inner_expr.formal_target_type;
			inner_ma.target_type = inner_expr.target_type;

			if (ma != null) {
				ma.inner = inner_ma;
				ma.checked = false;
				ma.check (context);
			} else if (ea != null) {
				ea.container = inner_ma;
				ea.checked = false;
				ea.check (context);
			} else if (se != null) {
				se.container = inner_ma;
				se.checked = false;
				se.check (context);
			}

			var false_block = (!void_return_type) ? new Block (source_reference) : null;
			if (false_block != null) {
				var false_stmt = new ExpressionStatement (new Assignment (new MemberAccess.simple (local.name, source_reference), new NullLiteral (source_reference), AssignmentOperator.SIMPLE, source_reference), source_reference);
				false_block.add_statement (false_stmt);
			}

			var condition = new BinaryExpression (BinaryOperator.INEQUALITY, new MemberAccess.simple (inner_local.name, nullable_expressions[index].source_reference), new NullLiteral (nullable_expressions[index].source_reference), nullable_expressions[index].source_reference);
			if_stmt = new IfStatement (condition, true_block, false_block, nullable_expressions[index].source_reference);
			if_stmt.check (context);

			true_block = new Block (nullable_expressions[index].source_reference);
			true_block.add_statement (inner_decl);
			true_block.add_statement (inner_stmt);
			true_block.add_statement (if_stmt);

			index--;
		}

		if (!void_return_type) {
			insert_statement (context.analyzer.insert_block, inner_decl);
			insert_statement (context.analyzer.insert_block, inner_stmt);
			insert_statement (context.analyzer.insert_block, if_stmt);

			var ma = new MemberAccess.simple (local.name, source_reference);
			ma.formal_target_type = formal_target_type;
			ma.target_type = target_type;
			ma.check (context);

			parent_node.replace_expression (this, ma);
		} else {
			var parent_stmt = parent_node as Statement;
			var parent_block = parent_stmt.parent_node as Block;

			parent_block.replace_statement (parent_stmt, if_stmt);
			parent_block.insert_before (if_stmt, inner_stmt);
			parent_block.insert_before (inner_stmt, inner_decl);
		}

		return true;
	}
}
