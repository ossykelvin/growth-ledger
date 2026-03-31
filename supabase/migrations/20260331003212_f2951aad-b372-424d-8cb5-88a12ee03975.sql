
-- Create enum for module permissions
CREATE TYPE public.app_module AS ENUM ('invoices', 'transactions', 'pnl', 'vat', 'paye', 'reports', 'users');
CREATE TYPE public.access_level AS ENUM ('none', 'view', 'edit', 'admin');

-- Create timestamp update function
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- Profiles table
CREATE TABLE public.tbl_profiles (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.tbl_profiles ENABLE ROW LEVEL SECURITY;

-- User roles table (separate from profiles per security guidelines)
CREATE TABLE public.tbl_user_roles (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  module app_module NOT NULL,
  access access_level NOT NULL DEFAULT 'none',
  UNIQUE (user_id, module)
);

ALTER TABLE public.tbl_user_roles ENABLE ROW LEVEL SECURITY;

-- Security definer function for role checks
CREATE OR REPLACE FUNCTION public.has_module_access(_user_id UUID, _module app_module, _min_access access_level)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tbl_user_roles
    WHERE user_id = _user_id
      AND module = _module
      AND CASE
        WHEN _min_access = 'view' THEN access IN ('view', 'edit', 'admin')
        WHEN _min_access = 'edit' THEN access IN ('edit', 'admin')
        WHEN _min_access = 'admin' THEN access = 'admin'
        ELSE true
      END
  )
$$;

CREATE OR REPLACE FUNCTION public.is_user_admin(_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tbl_user_roles
    WHERE user_id = _user_id
      AND module = 'users'
      AND access = 'admin'
  )
$$;

-- Invoices table
CREATE TABLE public.tbl_invoices (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invoice_number TEXT NOT NULL,
  client TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('paid', 'pending', 'overdue', 'draft')),
  issue_date DATE NOT NULL DEFAULT CURRENT_DATE,
  due_date DATE NOT NULL DEFAULT (CURRENT_DATE + INTERVAL '30 days'),
  items JSONB NOT NULL DEFAULT '[]',
  notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.tbl_invoices ENABLE ROW LEVEL SECURITY;

-- Transactions table
CREATE TABLE public.tbl_transactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  description TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  type TEXT NOT NULL CHECK (type IN ('inflow', 'outflow')),
  category TEXT NOT NULL DEFAULT 'Uncategorized',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('completed', 'pending', 'overdue')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.tbl_transactions ENABLE ROW LEVEL SECURITY;

-- VAT returns table
CREATE TABLE public.tbl_vat_returns (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  quarter TEXT NOT NULL,
  output_vat NUMERIC(12,2) NOT NULL DEFAULT 0,
  input_vat NUMERIC(12,2) NOT NULL DEFAULT 0,
  net_vat NUMERIC(12,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'due' CHECK (status IN ('filed', 'due', 'overdue')),
  deadline DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.tbl_vat_returns ENABLE ROW LEVEL SECURITY;

-- PAYE employees table
CREATE TABLE public.tbl_paye_employees (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT '',
  gross_pay NUMERIC(12,2) NOT NULL DEFAULT 0,
  tax NUMERIC(12,2) NOT NULL DEFAULT 0,
  ni NUMERIC(12,2) NOT NULL DEFAULT 0,
  net_pay NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.tbl_paye_employees ENABLE ROW LEVEL SECURITY;

-- RLS Policies for tbl_profiles
CREATE POLICY "Users can view own profile" ON public.tbl_profiles FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Admins can view all profiles" ON public.tbl_profiles FOR SELECT USING (public.is_user_admin(auth.uid()));
CREATE POLICY "Users can update own profile" ON public.tbl_profiles FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own profile" ON public.tbl_profiles FOR INSERT WITH CHECK (auth.uid() = user_id);

-- RLS Policies for tbl_user_roles
CREATE POLICY "Users can view own roles" ON public.tbl_user_roles FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Admins can manage all roles" ON public.tbl_user_roles FOR ALL USING (public.is_user_admin(auth.uid()));

-- RLS Policies for tbl_invoices
CREATE POLICY "Users can manage own invoices" ON public.tbl_invoices FOR ALL USING (auth.uid() = user_id);

-- RLS Policies for tbl_transactions
CREATE POLICY "Users can manage own transactions" ON public.tbl_transactions FOR ALL USING (auth.uid() = user_id);

-- RLS Policies for tbl_vat_returns
CREATE POLICY "Users can manage own vat returns" ON public.tbl_vat_returns FOR ALL USING (auth.uid() = user_id);

-- RLS Policies for tbl_paye_employees
CREATE POLICY "Users can manage own employees" ON public.tbl_paye_employees FOR ALL USING (auth.uid() = user_id);

-- Triggers for updated_at
CREATE TRIGGER update_tbl_profiles_updated_at BEFORE UPDATE ON public.tbl_profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_tbl_invoices_updated_at BEFORE UPDATE ON public.tbl_invoices FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_tbl_transactions_updated_at BEFORE UPDATE ON public.tbl_transactions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_tbl_vat_returns_updated_at BEFORE UPDATE ON public.tbl_vat_returns FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_tbl_paye_employees_updated_at BEFORE UPDATE ON public.tbl_paye_employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Auto-create profile and grant admin to first user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_count INT;
BEGIN
  INSERT INTO public.tbl_profiles (user_id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', ''), NEW.email);

  SELECT COUNT(*) INTO user_count FROM public.tbl_profiles;

  IF user_count <= 1 THEN
    INSERT INTO public.tbl_user_roles (user_id, module, access)
    VALUES
      (NEW.id, 'invoices', 'admin'),
      (NEW.id, 'transactions', 'admin'),
      (NEW.id, 'pnl', 'admin'),
      (NEW.id, 'vat', 'admin'),
      (NEW.id, 'paye', 'admin'),
      (NEW.id, 'reports', 'admin'),
      (NEW.id, 'users', 'admin');
  ELSE
    INSERT INTO public.tbl_user_roles (user_id, module, access)
    VALUES
      (NEW.id, 'invoices', 'view'),
      (NEW.id, 'transactions', 'view'),
      (NEW.id, 'pnl', 'view'),
      (NEW.id, 'vat', 'view'),
      (NEW.id, 'paye', 'view'),
      (NEW.id, 'reports', 'view'),
      (NEW.id, 'users', 'none');
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
